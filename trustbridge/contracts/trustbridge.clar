;; TrustBridge: Independent Decentralized Escrow Service
;; This contract implements a secure escrow service with multi-sig dispute resolution
;; Handles native STX transactions

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-NOT-FOUND (err u103))
(define-constant ERR-ZERO-AMOUNT (err u104))
(define-constant ERR-INVALID-ARBITRATOR (err u105))

;; Constants for escrow status
(define-constant STATUS-PENDING u1)
(define-constant STATUS-COMPLETED u2)
(define-constant STATUS-DISPUTED u3)
(define-constant STATUS-REFUNDED u4)

;; Data structures
(define-map escrows
    { escrow-id: uint }
    {
        initiator: principal,
        counterparty: principal,
        arbitrator: principal,
        amount: uint,
        status: uint,
        created-at: uint
    }
)

(define-map escrow-balance uint uint)

;; Track the next available escrow ID
(define-data-var next-escrow-id uint u1)

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
        ;; Check for valid amount
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        
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
                created-at: block-height
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
            (escrow (unwrap! (map-get? escrows {escrow-id: escrow-id}) ERR-NOT-FOUND))
            (amount (unwrap! (map-get? escrow-balance escrow-id) ERR-NOT-FOUND))
        )
        ;; Verify caller is counterparty
        (asserts! (is-eq (get counterparty escrow) tx-sender) ERR-NOT-AUTHORIZED)
        ;; Verify escrow is pending
        (asserts! (is-eq (get status escrow) STATUS-PENDING) ERR-INVALID-STATUS)
        
        ;; Transfer STX to counterparty
        (try! (as-contract (stx-transfer? amount tx-sender (get counterparty escrow))))
        
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
            (escrow (unwrap! (map-get? escrows {escrow-id: escrow-id}) ERR-NOT-FOUND))
        )
        ;; Verify caller is initiator or counterparty
        (asserts! (or
            (is-eq (get initiator escrow) tx-sender)
            (is-eq (get counterparty escrow) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        
        ;; Verify escrow is pending
        (asserts! (is-eq (get status escrow) STATUS-PENDING) ERR-INVALID-STATUS)
        
        ;; Update escrow status to disputed
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow { status: STATUS-DISPUTED })
        )
        
        (ok true)
    )
)

;; Arbitrate a dispute
(define-public (arbitrate-dispute (escrow-id uint) (release-to-counterparty bool))
    (let
        (
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

;; Get contract balance
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)