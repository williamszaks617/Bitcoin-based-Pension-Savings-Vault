(define-constant PENALTY-BPS u1000)
(define-constant EMERGENCY-PENALTY-BPS u2500)
(define-constant EMERGENCY-COOLDOWN-BLOCKS u1008)
(define-constant MAX-BPS u10000)
(define-constant MIN-RETIREMENT-AGE u60)
(define-constant DEFAULT-INACTIVITY-BLOCKS u262800)
(define-constant AGE-ADJUSTMENT-COOLDOWN-BLOCKS u52560)
(define-constant MAX-RETIREMENT-AGE u75)
(define-map users
    principal
    {
        balance: uint,
        start-height: uint,
        retirement-age: uint,
        last-activity: uint,
    }
)
(define-map emergency-requests
    principal
    {
        amount: uint,
        request-height: uint,
    }
)
(define-map beneficiaries
    principal
    {
        beneficiary: principal,
        inactivity-blocks: uint,
    }
)
(define-map age-adjustment-requests
    principal
    {
        new-retirement-age: uint,
        request-height: uint,
    }
)
(define-read-only (get-user (user principal))
    (map-get? users user)
)
(define-public (enroll (retirement-age uint))
    (begin
        (asserts! (>= retirement-age MIN-RETIREMENT-AGE) (err u100))
        (asserts! (not (is-some (map-get? users tx-sender))) (err u101))
        (map-set users tx-sender {
            balance: u0,
            start-height: burn-block-height,
            retirement-age: retirement-age,
            last-activity: burn-block-height,
        })
        (ok true)
    )
)
(define-public (deposit (amount uint))
    (let ((user (map-get? users tx-sender)))
        (match user
            udata (begin
                (asserts! (> amount u0) (err u102))
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set users tx-sender {
                    balance: (+ (get balance udata) amount),
                    start-height: (get start-height udata),
                    retirement-age: (get retirement-age udata),
                    last-activity: burn-block-height,
                })
                (ok amount)
            )
            (err u103)
        )
    )
)
(define-read-only (is-eligible (user principal))
    (match (map-get? users user)
        udata (let (
                (start-block (get start-height udata))
                (retirement-age (get retirement-age udata))
                (current-block burn-block-height)
            )
            (ok (>= (- current-block start-block) (* retirement-age u52560)))
        )
        (err u104)
    )
)
(define-public (withdraw)
    (match (map-get? users tx-sender)
        user-data (let (
                (eligible (unwrap-panic (is-eligible tx-sender)))
                (amount (get balance user-data))
                (penalty (if eligible
                    u0
                    (/ (* amount PENALTY-BPS) MAX-BPS)
                ))
                (final-amount (- amount penalty))
            )
            (begin
                (asserts! (> amount u0) (err u105))
                (map-set users tx-sender {
                    balance: u0,
                    start-height: (get start-height user-data),
                    retirement-age: (get retirement-age user-data),
                    last-activity: burn-block-height,
                })
                (stx-transfer? final-amount (as-contract tx-sender) tx-sender)
            )
        )
        (err u106)
    )
)
(define-public (get-balance)
    (match (map-get? users tx-sender)
        udata (ok (get balance udata))
        (err u107)
    )
)
(define-read-only (get-contract-balance)
    (ok (stx-get-balance (as-contract tx-sender)))
)
(define-public (request-emergency-withdrawal (amount uint))
    (match (map-get? users tx-sender)
        user-data (begin
            (asserts! (> amount u0) (err u108))
            (asserts! (<= amount (get balance user-data)) (err u109))
            (asserts! (is-none (map-get? emergency-requests tx-sender))
                (err u110)
            )
            (map-set emergency-requests tx-sender {
                amount: amount,
                request-height: burn-block-height,
            })
            (ok amount)
        )
        (err u111)
    )
)
(define-public (execute-emergency-withdrawal)
    (match (map-get? emergency-requests tx-sender)
        request-data (let (
                (request-height (get request-height request-data))
                (requested-amount (get amount request-data))
                (current-height burn-block-height)
                (penalty (/ (* requested-amount EMERGENCY-PENALTY-BPS) MAX-BPS))
                (final-amount (- requested-amount penalty))
            )
            (begin
                (asserts!
                    (>= (- current-height request-height)
                        EMERGENCY-COOLDOWN-BLOCKS
                    )
                    (err u112)
                )
                (match (map-get? users tx-sender)
                    user-data (let ((current-balance (get balance user-data)))
                        (begin
                            (asserts! (>= current-balance requested-amount)
                                (err u113)
                            )
                            (map-set users tx-sender {
                                balance: (- current-balance requested-amount),
                                start-height: (get start-height user-data),
                                retirement-age: (get retirement-age user-data),
                                last-activity: burn-block-height,
                            })
                            (map-delete emergency-requests tx-sender)
                            (stx-transfer? final-amount (as-contract tx-sender)
                                tx-sender
                            )
                        )
                    )
                    (err u114)
                )
            )
        )
        (err u115)
    )
)
(define-public (cancel-emergency-withdrawal)
    (match (map-get? emergency-requests tx-sender)
        request-data (begin
            (map-delete emergency-requests tx-sender)
            (ok true)
        )
        (err u116)
    )
)
(define-read-only (get-emergency-request (user principal))
    (map-get? emergency-requests user)
)
(define-public (set-beneficiary
        (beneficiary-address principal)
        (inactivity-blocks uint)
    )
    (match (map-get? users tx-sender)
        user-data (begin
            (asserts! (> inactivity-blocks u0) (err u117))
            (map-set beneficiaries tx-sender {
                beneficiary: beneficiary-address,
                inactivity-blocks: inactivity-blocks,
            })
            (ok beneficiary-address)
        )
        (err u118)
    )
)
(define-read-only (get-beneficiary (vault-owner principal))
    (map-get? beneficiaries vault-owner)
)
(define-read-only (can-beneficiary-claim (vault-owner principal))
    (match (map-get? users vault-owner)
        user-data (match (map-get? beneficiaries vault-owner)
            beneficiary-data (let (
                    (last-activity (get last-activity user-data))
                    (inactivity-threshold (get inactivity-blocks beneficiary-data))
                    (current-height burn-block-height)
                )
                (ok (>= (- current-height last-activity) inactivity-threshold))
            )
            (err u119)
        )
        (err u120)
    )
)
(define-public (beneficiary-claim (vault-owner principal))
    (let ((claimant tx-sender))
        (match (map-get? beneficiaries vault-owner)
            beneficiary-data (begin
                (asserts! (is-eq claimant (get beneficiary beneficiary-data))
                    (err u121)
                )
                (asserts! (unwrap-panic (can-beneficiary-claim vault-owner))
                    (err u122)
                )
                (match (map-get? users vault-owner)
                    user-data (let ((vault-balance (get balance user-data)))
                        (begin
                            (asserts! (> vault-balance u0) (err u123))
                            (map-set users vault-owner {
                                balance: u0,
                                start-height: (get start-height user-data),
                                retirement-age: (get retirement-age user-data),
                                last-activity: (get last-activity user-data),
                            })
                            (map-delete beneficiaries vault-owner)
                            (stx-transfer? vault-balance (as-contract tx-sender)
                                claimant
                            )
                        )
                    )
                    (err u124)
                )
            )
            (err u125)
        )
    )
)
(define-public (reset-activity)
    (match (map-get? users tx-sender)
        user-data (begin
            (map-set users tx-sender {
                balance: (get balance user-data),
                start-height: (get start-height user-data),
                retirement-age: (get retirement-age user-data),
                last-activity: burn-block-height,
            })
            (ok burn-block-height)
        )
        (err u126)
    )
)
(define-public (request-age-adjustment (new-retirement-age uint))
    (match (map-get? users tx-sender)
        user-data (begin
            (asserts! (>= new-retirement-age MIN-RETIREMENT-AGE) (err u127))
            (asserts! (<= new-retirement-age MAX-RETIREMENT-AGE) (err u128))
            (asserts!
                (not (is-eq new-retirement-age (get retirement-age user-data)))
                (err u129)
            )
            (asserts! (is-none (map-get? age-adjustment-requests tx-sender))
                (err u130)
            )
            (map-set age-adjustment-requests tx-sender {
                new-retirement-age: new-retirement-age,
                request-height: burn-block-height,
            })
            (ok new-retirement-age)
        )
        (err u131)
    )
)
(define-public (execute-age-adjustment)
    (match (map-get? age-adjustment-requests tx-sender)
        request-data (let (
                (request-height (get request-height request-data))
                (new-age (get new-retirement-age request-data))
                (current-height burn-block-height)
            )
            (begin
                (asserts!
                    (>= (- current-height request-height)
                        AGE-ADJUSTMENT-COOLDOWN-BLOCKS
                    )
                    (err u132)
                )
                (match (map-get? users tx-sender)
                    user-data (begin
                        (map-set users tx-sender {
                            balance: (get balance user-data),
                            start-height: (get start-height user-data),
                            retirement-age: new-age,
                            last-activity: burn-block-height,
                        })
                        (map-delete age-adjustment-requests tx-sender)
                        (ok new-age)
                    )
                    (err u133)
                )
            )
        )
        (err u134)
    )
)
(define-public (cancel-age-adjustment)
    (match (map-get? age-adjustment-requests tx-sender)
        request-data (begin
            (map-delete age-adjustment-requests tx-sender)
            (ok true)
        )
        (err u135)
    )
)
(define-read-only (get-age-adjustment-request (user principal))
    (map-get? age-adjustment-requests user)
)
