;; TrustBridge: Independent Decentralized Escrow Service with Reputation System
;; Implements secure escrow with multi-sig dispute resolution and reputation tracking

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-NOT-FOUND (err u103))
(define-constant ERR-ZERO-AMOUNT (err u104))
(define-constant ERR-INVALID-ARBITRATOR (err u105))
(define-constant ERR-INVALID-COUNTERPARTY (err u106))
(define-constant ERR-INVALID-ESCROW-ID (err u107))
(define-constant ERR-SELF-TRANSFER (err u108))

;; Constants for escrow status
(define-constant STATUS-PENDING u1)
(define-constant STATUS-COMPLETED u2)
(define-constant STATUS-DISPUTED u3)
(define-constant STATUS-REFUNDED u4)

;; Reputation score modifiers
(define-constant SCORE-NEW-USER u50)           
(define-constant SCORE-SUCCESSFUL-TRADE u5)    
(define-constant SCORE-DISPUTE-INITIATED u3)   
(define-constant SCORE-DISPUTE-LOST u10)       
(define-constant SCORE-ARBITRATOR-RESOLVED u2) 

;; Data structures
(define-map escrows
    { escrow-id: uint }
    {
        initiator: principal,
        counterparty: principal,
        arbitrator: principal,
        amount: uint,
        status: uint,
        created-at: uint,
        dispute-initiator: (optional principal)
    }
)

(define-map escrow-balance uint uint)

;; Reputation tracking
(define-map user-reputation principal 
    {
        score: uint,
        total-trades: uint,
        successful-trades: uint,
        disputes-initiated: uint,
        disputes-lost: uint
    }
)

(define-map arbitrator-reputation principal 
    {
        score: uint,
        cases-resolved: uint,
        active-since: uint
    }
)

;; Track the next available escrow ID
(define-data-var next-escrow-id uint u1)

;; Validate escrow ID
(define-private (is-valid-escrow-id (escrow-id uint))
    (and 
        (> escrow-id u0)
        (< escrow-id (var-get next-escrow-id))
    )
)

;; Validate principal is not contract caller
(define-private (is-valid-counterparty (counterparty principal))
    (not (is-eq tx-sender counterparty))
)

;; Validate arbitrator
(define-private (is-valid-arbitrator (arbitrator principal))
    (and 
        (not (is-eq tx-sender arbitrator))
        (is-some (map-get? arbitrator-reputation arbitrator))
    )
)

;; Initialize or get user reputation
(define-private (get-or-init-user-reputation (user principal)) 
    (default-to
        {
            score: SCORE-NEW-USER,
            total-trades: u0,
            successful-trades: u0,
            disputes-initiated: u0,
            disputes-lost: u0
        }
        (map-get? user-reputation user)
    )
)

;; Initialize or get arbitrator reputation
(define-private (get-or-init-arbitrator-reputation (arbitrator principal))
    (default-to
        {
            score: SCORE-NEW-USER,
            cases-resolved: u0,
            active-since: block-height
        }
        (map-get? arbitrator-reputation arbitrator)
    )
)

;; Update user reputation after successful trade
(define-private (update-successful-trade-reputation (user principal))
    (let (
        (current-rep (get-or-init-user-reputation user))
    )
        (map-set user-reputation user
            (merge current-rep {
                score: (+ (get score current-rep) SCORE-SUCCESSFUL-TRADE),
                total-trades: (+ (get total-trades current-rep) u1),
                successful-trades: (+ (get successful-trades current-rep) u1)
            })
        )
    )
)

;; Update reputation for dispute initiation
(define-private (update-dispute-initiated-reputation (user principal))
    (let (
        (current-rep (get-or-init-user-reputation user))
    )
        (map-set user-reputation user
            (merge current-rep {
                score: (- (get score current-rep) SCORE-DISPUTE-INITIATED),
                disputes-initiated: (+ (get disputes-initiated current-rep) u1)
            })
        )
    )
)

;; Update reputation after dispute resolution
(define-private (update-dispute-resolution-reputation (winner principal) (loser principal))
    (let (
        (winner-rep (get-or-init-user-reputation winner))
        (loser-rep (get-or-init-user-reputation loser))
    )
        (map-set user-reputation winner
            (merge winner-rep {
                successful-trades: (+ (get successful-trades winner-rep) u1)
            })
        )
        (map-set user-reputation loser
            (merge loser-rep {
                score: (- (get score loser-rep) SCORE-DISPUTE-LOST),
                disputes-lost: (+ (get disputes-lost loser-rep) u1)
            })
        )
    )
)

;; Update arbitrator reputation
(define-private (update-arbitrator-reputation (arbitrator principal))
    (let (
        (current-rep (get-or-init-arbitrator-reputation arbitrator))
    )
        (map-set arbitrator-reputation arbitrator
            (merge current-rep {
                score: (+ (get score current-rep) SCORE-ARBITRATOR-RESOLVED),
                cases-resolved: (+ (get cases-resolved current-rep) u1)
            })
        )
    )
)

;; Create new escrow
(define-public (create-escrow 
    (counterparty principal)
    (arbitrator principal)
    (amount uint)
)
    (let
        (
            (escrow-id (var-get next-escrow-id))
        )
        ;; Validate inputs
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (is-valid-counterparty counterparty) ERR-INVALID-COUNTERPARTY)
        (asserts! (is-valid-arbitrator arbitrator) ERR-INVALID-ARBITRATOR)
        
        ;; Initialize reputations if needed
        (get-or-init-user-reputation tx-sender)
        ;; Safe to call after validation
        (get-or-init-user-reputation counterparty)
        (get-or-init-arbitrator-reputation arbitrator)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Create escrow record
        (map-set escrows
            { escrow-id: escrow-id }
            {
                initiator: tx-sender,
                counterparty: counterparty,
                arbitrator: arbitrator,
                amount: amount,
                status: STATUS-PENDING,
                created-at: block-height,
                dispute-initiator: none
            }
        )
        
        ;; Update escrow balance
        (map-set escrow-balance escrow-id amount)
        
        ;; Increment escrow ID
        (var-set next-escrow-id (+ escrow-id u1))
        
        (ok escrow-id)
    )
)

;; Complete escrow and release funds to counterparty
(define-public (complete-escrow (escrow-id uint))
    (let
        (
            ;; Validate escrow-id first
            (valid (asserts! (is-valid-escrow-id escrow-id) ERR-INVALID-ESCROW-ID))
            (escrow (unwrap! (map-get? escrows {escrow-id: escrow-id}) ERR-NOT-FOUND))
            (amount (unwrap! (map-get? escrow-balance escrow-id) ERR-NOT-FOUND))
        )
        ;; Verify caller is counterparty
        (asserts! (is-eq (get counterparty escrow) tx-sender) ERR-NOT-AUTHORIZED)
        ;; Verify escrow is pending
        (asserts! (is-eq (get status escrow) STATUS-PENDING) ERR-INVALID-STATUS)
        
        ;; Transfer STX to counterparty
        (try! (as-contract (stx-transfer? amount tx-sender (get counterparty escrow))))
        
        ;; Update reputations for successful trade
        (update-successful-trade-reputation (get initiator escrow))
        (update-successful-trade-reputation (get counterparty escrow))
        
        ;; Update escrow status
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow { status: STATUS-COMPLETED })
        )
        
        ;; Clear escrow balance
        (map-delete escrow-balance escrow-id)
        
        (ok true)
    )
)

;; Initiate a dispute
(define-public (initiate-dispute (escrow-id uint))
    (let
        (
            ;; Validate escrow-id first
            (valid (asserts! (is-valid-escrow-id escrow-id) ERR-INVALID-ESCROW-ID))
            (escrow (unwrap! (map-get? escrows {escrow-id: escrow-id}) ERR-NOT-FOUND))
        )
        ;; Verify caller is initiator or counterparty
        (asserts! (or
            (is-eq (get initiator escrow) tx-sender)
            (is-eq (get counterparty escrow) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        
        ;; Verify escrow is pending
        (asserts! (is-eq (get status escrow) STATUS-PENDING) ERR-INVALID-STATUS)
        
        ;; Update dispute initiator reputation
        (update-dispute-initiated-reputation tx-sender)
        
        ;; Update escrow status and record dispute initiator
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow { 
                status: STATUS-DISPUTED,
                dispute-initiator: (some tx-sender)
            })
        )
        
        (ok true)
    )
)

;; Arbitrate a dispute
(define-public (arbitrate-dispute (escrow-id uint) (release-to-counterparty bool))
    (let
        (
            ;; Validate escrow-id first
            (valid (asserts! (is-valid-escrow-id escrow-id) ERR-INVALID-ESCROW-ID))
            (escrow (unwrap! (map-get? escrows {escrow-id: escrow-id}) ERR-NOT-FOUND))
            (amount (unwrap! (map-get? escrow-balance escrow-id) ERR-NOT-FOUND))
        )
        ;; Verify caller is arbitrator
        (asserts! (is-eq (get arbitrator escrow) tx-sender) ERR-NOT-AUTHORIZED)
        ;; Verify escrow is disputed
        (asserts! (is-eq (get status escrow) STATUS-DISPUTED) ERR-INVALID-STATUS)
        
        ;; Transfer STX based on arbitrator decision
        (if release-to-counterparty
            (try! (as-contract (stx-transfer? amount tx-sender (get counterparty escrow))))
            (try! (as-contract (stx-transfer? amount tx-sender (get initiator escrow))))
        )
        
        ;; Update reputations
        (if release-to-counterparty
            (update-dispute-resolution-reputation 
                (get counterparty escrow)
                (get initiator escrow)
            )
            (update-dispute-resolution-reputation 
                (get initiator escrow)
                (get counterparty escrow)
            )
        )
        
        ;; Update arbitrator reputation
        (update-arbitrator-reputation tx-sender)
        
        ;; Update escrow status
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow { status: STATUS-COMPLETED })
        )
        
        ;; Clear escrow balance
        (map-delete escrow-balance escrow-id)
        
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrows {escrow-id: escrow-id})
)

(define-read-only (get-escrow-balance (escrow-id uint))
    (map-get? escrow-balance escrow-id)
)

(define-read-only (get-user-reputation (user principal))
    (get-or-init-user-reputation user)
)

(define-read-only (get-arbitrator-reputation (arbitrator principal))
    (get-or-init-arbitrator-reputation arbitrator)
)

;; Get contract balance
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)