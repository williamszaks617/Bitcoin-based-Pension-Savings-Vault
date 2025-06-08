(define-constant PENALTY-BPS u1000)
(define-constant MAX-BPS u10000)
(define-constant MIN-RETIREMENT-AGE u60)
(define-map users
    principal
    {
        balance: uint,
        start-height: uint,
        retirement-age: uint,
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
