# TrustBridge: Decentralized Escrow Service with Reputation System

TrustBridge is a secure, decentralized escrow service implemented as a smart contract on the Stacks blockchain. It facilitates trustless transactions between parties while maintaining a reputation system for all participants.

## Features

### Core Escrow Functionality
- **Secure Asset Lock**: Safely lock STX tokens in the smart contract
- **Multi-party Transactions**: Support for initiator, counterparty, and arbitrator roles
- **Dispute Resolution**: Built-in dispute mechanism with arbitrator oversight
- **Automatic Settlement**: Automatic release of funds upon successful completion

### Reputation System
- **User Reputation Tracking**
  - Individual reputation scores for all participants
  - History of successful trades
  - Dispute patterns and resolution outcomes
  - Performance metrics

- **Arbitrator Reputation**
  - Track record of resolved cases
  - Longevity in the system
  - Performance scoring

### Security Features
- Input validation for all parameters
- Protection against self-transfers
- Arbitrator validation
- Escrow ID validation
- Status-based transaction controls

## Technical Details

### Contract Architecture

```clarity
;; Main Data Structures
escrows: Map
user-reputation: Map
arbitrator-reputation: Map
escrow-balance: Map
```

### Reputation Scoring

| Action | Score Change |
|--------|-------------|
| New User | +50 points |
| Successful Trade | +5 points |
| Initiate Dispute | -3 points |
| Lose Dispute | -10 points |
| Resolve Case (Arbitrator) | +2 points |

### Status Codes

- `STATUS-PENDING (u1)`: Initial state
- `STATUS-COMPLETED (u2)`: Successfully completed
- `STATUS-DISPUTED (u3)`: Under dispute
- `STATUS-REFUNDED (u4)`: Funds returned

### Error Codes

- `ERR-NOT-AUTHORIZED (u100)`
- `ERR-ALREADY-EXISTS (u101)`
- `ERR-INVALID-STATUS (u102)`
- `ERR-NOT-FOUND (u103)`
- `ERR-ZERO-AMOUNT (u104)`
- `ERR-INVALID-ARBITRATOR (u105)`
- `ERR-INVALID-COUNTERPARTY (u106)`
- `ERR-INVALID-ESCROW-ID (u107)`
- `ERR-SELF-TRANSFER (u108)`

## Setup and Deployment

### Prerequisites
- Clarinet installed
- Stacks blockchain development environment
- STX tokens for testing

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/trustbridge.git
cd trustbridge
```

2. Install dependencies:
```bash
clarinet requirements
```

3. Run tests:
```bash
clarinet test
```

### Deployment

1. Build the contract:
```bash
clarinet build
```

2. Deploy using Clarinet:
```bash
clarinet deploy
```

## Usage Guide

### Creating an Escrow

```clarity
(contract-call? .trustbridge create-escrow 
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM  ;; counterparty
    'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG  ;; arbitrator
    u1000000                                      ;; amount in uSTX
)
```

### Completing an Escrow

```clarity
(contract-call? .trustbridge complete-escrow u1)  ;; escrow-id
```

### Initiating a Dispute

```clarity
(contract-call? .trustbridge initiate-dispute u1)  ;; escrow-id
```

### Arbitrating a Dispute

```clarity
(contract-call? .trustbridge arbitrate-dispute 
    u1    ;; escrow-id
    true  ;; release to counterparty
)
```

### Checking Reputation

```clarity
(contract-call? .trustbridge get-user-reputation 
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
)
```

## Best Practices

1. **Before Creating Escrow**
   - Verify arbitrator's reputation
   - Check counterparty's trading history
   - Ensure sufficient funds

2. **During Transaction**
   - Monitor escrow status
   - Keep communication clear
   - Document all agreements

3. **Dispute Resolution**
   - Provide evidence promptly
   - Follow arbitrator instructions
   - Maintain professional conduct

## Contributing

We welcome contributions to TrustBridge! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to your branch
5. Create a Pull Request

## Roadmap

- [ ] Multi-token support
- [ ] Time-locked escrows
- [ ] Reputation staking
- [ ] Arbitrator DAO
- [ ] Cross-chain bridges

## Acknowledgments

- Stacks Foundation
- Clarity Lang Team
- Our community contributors