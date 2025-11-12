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

;; ===== PENSION GOAL TRACKER FEATURE =====
;; Independent goal tracking system with milestones and achievements

;; Goal Tracker Constants
(define-constant MIN-GOAL-AMOUNT u10000000) ;; 10 STX minimum goal
(define-constant MAX-GOAL-AMOUNT u1000000000000) ;; 1M STX maximum goal
(define-constant MIN-MILESTONE-PERCENTAGE u5) ;; 5% minimum milestone
(define-constant MAX-MILESTONE-PERCENTAGE u100) ;; 100% maximum milestone
(define-constant GOAL-REWARD-BPS u100) ;; 1% reward for achieving milestones
(define-constant MAX-MILESTONES-PER-GOAL u10) ;; Maximum 10 milestones per goal
(define-constant MIN-GOAL-DURATION-BLOCKS u52560) ;; 1 year minimum
(define-constant MAX-GOAL-DURATION-BLOCKS u525600) ;; 10 years maximum

;; Goal Tracker Error Constants
(define-constant ERR-GOAL-EXISTS u200)
(define-constant ERR-GOAL-NOT-FOUND u201)
(define-constant ERR-INVALID-GOAL-AMOUNT u202)
(define-constant ERR-INVALID-GOAL-DURATION u203)
(define-constant ERR-INVALID-MILESTONE-PERCENTAGE u204)
(define-constant ERR-MILESTONE-NOT-ACHIEVED u205)
(define-constant ERR-MILESTONE-ALREADY-CLAIMED u206)
(define-constant ERR-GOAL-NOT-ACTIVE u207)
(define-constant ERR-GOAL-EXPIRED u208)
(define-constant ERR-TOO-MANY-MILESTONES u209)
(define-constant ERR-USER-NOT-ENROLLED u210)

;; Goal Data Maps
(define-map pension-goals
    principal
    {
        target-amount: uint,
        current-progress: uint,
        start-height: uint,
        target-height: uint,
        is-active: bool,
        total-rewards-earned: uint,
    }
)

(define-map goal-milestones
    {
        user: principal,
        milestone-id: uint,
    }
    {
        percentage: uint,
        target-amount: uint,
        is-achieved: bool,
        is-claimed: bool,
        achievement-height: (optional uint),
    }
)

(define-map user-milestone-count
    principal
    uint
)

(define-map goal-statistics
    principal
    {
        total-goals-created: uint,
        total-goals-completed: uint,
        total-milestones-achieved: uint,
        lifetime-rewards: uint,
    }
)

;; Goal Management Functions

(define-public (create-pension-goal
        (target-amount uint)
        (duration-blocks uint)
    )
    (let ((user tx-sender))
        (begin
            ;; Validate user is enrolled in pension system
            (asserts! (is-some (map-get? users user)) (err ERR-USER-NOT-ENROLLED))

            ;; Validate no existing active goal
            (asserts! (is-none (map-get? pension-goals user))
                (err ERR-GOAL-EXISTS)
            )

            ;; Validate goal parameters
            (asserts!
                (and
                    (>= target-amount MIN-GOAL-AMOUNT)
                    (<= target-amount MAX-GOAL-AMOUNT)
                )
                (err ERR-INVALID-GOAL-AMOUNT)
            )
            (asserts!
                (and
                    (>= duration-blocks MIN-GOAL-DURATION-BLOCKS)
                    (<= duration-blocks MAX-GOAL-DURATION-BLOCKS)
                )
                (err ERR-INVALID-GOAL-DURATION)
            )

            ;; Create goal
            (map-set pension-goals user {
                target-amount: target-amount,
                current-progress: u0,
                start-height: burn-block-height,
                target-height: (+ burn-block-height duration-blocks),
                is-active: true,
                total-rewards-earned: u0,
            })

            ;; Initialize milestone count
            (map-set user-milestone-count user u0)

            ;; Update statistics
            (match (map-get? goal-statistics user)
                stats (map-set goal-statistics user {
                    total-goals-created: (+ (get total-goals-created stats) u1),
                    total-goals-completed: (get total-goals-completed stats),
                    total-milestones-achieved: (get total-milestones-achieved stats),
                    lifetime-rewards: (get lifetime-rewards stats),
                })
                (map-set goal-statistics user {
                    total-goals-created: u1,
                    total-goals-completed: u0,
                    total-milestones-achieved: u0,
                    lifetime-rewards: u0,
                })
            )

            (ok target-amount)
        )
    )
)

(define-public (add-goal-milestone (percentage uint))
    (let (
            (user tx-sender)
            (milestone-count (default-to u0 (map-get? user-milestone-count user)))
        )
        (begin
            ;; Validate active goal exists
            (asserts! (is-some (map-get? pension-goals user))
                (err ERR-GOAL-NOT-FOUND)
            )

            ;; Validate milestone parameters
            (asserts!
                (and
                    (>= percentage MIN-MILESTONE-PERCENTAGE)
                    (<= percentage MAX-MILESTONE-PERCENTAGE)
                )
                (err ERR-INVALID-MILESTONE-PERCENTAGE)
            )
            (asserts! (< milestone-count MAX-MILESTONES-PER-GOAL)
                (err ERR-TOO-MANY-MILESTONES)
            )

            ;; Get goal data
            (match (map-get? pension-goals user)
                goal-data (let (
                        (target-amount (get target-amount goal-data))
                        (milestone-target (/ (* target-amount percentage) u100))
                    )
                    (begin
                        ;; Create milestone
                        (map-set goal-milestones {
                            user: user,
                            milestone-id: milestone-count,
                        } {
                            percentage: percentage,
                            target-amount: milestone-target,
                            is-achieved: false,
                            is-claimed: false,
                            achievement-height: none,
                        })

                        ;; Update milestone count
                        (map-set user-milestone-count user (+ milestone-count u1))

                        (ok milestone-count)
                    )
                )
                (err ERR-GOAL-NOT-FOUND)
            )
        )
    )
)

(define-public (update-goal-progress)
    (let ((user tx-sender))
        (match (map-get? pension-goals user)
            goal-data (match (map-get? users user)
                user-data (let (
                        (current-balance (get balance user-data))
                        (target-amount (get target-amount goal-data))
                        (milestone-count (default-to u0 (map-get? user-milestone-count user)))
                    )
                    (begin
                        ;; Update goal progress
                        (map-set pension-goals user {
                            target-amount: (get target-amount goal-data),
                            current-progress: current-balance,
                            start-height: (get start-height goal-data),
                            target-height: (get target-height goal-data),
                            is-active: (get is-active goal-data),
                            total-rewards-earned: (get total-rewards-earned goal-data),
                        })

                        ;; Check and update milestone achievements
                        (fold check-milestone-achievement
                            (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
                            current-balance
                        )

                        ;; Check if goal is completed
                        (if (>= current-balance target-amount)
                            (begin
                                (map-set pension-goals user {
                                    target-amount: target-amount,
                                    current-progress: current-balance,
                                    start-height: (get start-height goal-data),
                                    target-height: (get target-height goal-data),
                                    is-active: false,
                                    total-rewards-earned: (get total-rewards-earned goal-data),
                                })

                                ;; Update completion statistics
                                (match (map-get? goal-statistics user)
                                    stats (map-set goal-statistics user {
                                        total-goals-created: (get total-goals-created stats),
                                        total-goals-completed: (+ (get total-goals-completed stats) u1),
                                        total-milestones-achieved: (get total-milestones-achieved stats),
                                        lifetime-rewards: (get lifetime-rewards stats),
                                    })
                                    true
                                )
                                (ok "goal-completed")
                            )
                            (ok "progress-updated")
                        )
                    )
                )
                (err ERR-USER-NOT-ENROLLED)
            )
            (err ERR-GOAL-NOT-FOUND)
        )
    )
)

(define-private (check-milestone-achievement
        (milestone-id uint)
        (current-balance uint)
    )
    (let ((user tx-sender))
        (match (map-get? goal-milestones {
            user: user,
            milestone-id: milestone-id,
        })
            milestone-data (let (
                    (target-amount (get target-amount milestone-data))
                    (is-achieved (get is-achieved milestone-data))
                )
                (begin
                    (if (and (>= current-balance target-amount) (not is-achieved))
                        (begin
                            (map-set goal-milestones {
                                user: user,
                                milestone-id: milestone-id,
                            } {
                                percentage: (get percentage milestone-data),
                                target-amount: target-amount,
                                is-achieved: true,
                                is-claimed: (get is-claimed milestone-data),
                                achievement-height: (some burn-block-height),
                            })

                            ;; Update statistics
                            (match (map-get? goal-statistics user)
                                stats (map-set goal-statistics user {
                                    total-goals-created: (get total-goals-created stats),
                                    total-goals-completed: (get total-goals-completed stats),
                                    total-milestones-achieved: (+ (get total-milestones-achieved stats) u1),
                                    lifetime-rewards: (get lifetime-rewards stats),
                                })
                                true
                            )
                            current-balance
                        )
                        current-balance
                    )
                )
            )
            current-balance
        )
    )
)

(define-public (claim-milestone-reward (milestone-id uint))
    (let ((user tx-sender))
        (match (map-get? goal-milestones {
            user: user,
            milestone-id: milestone-id,
        })
            milestone-data (let (
                    (is-achieved (get is-achieved milestone-data))
                    (is-claimed (get is-claimed milestone-data))
                    (target-amount (get target-amount milestone-data))
                    (reward-amount (/ (* target-amount GOAL-REWARD-BPS) MAX-BPS))
                )
                (begin
                    ;; Validate milestone is achieved and not claimed
                    (asserts! is-achieved (err ERR-MILESTONE-NOT-ACHIEVED))
                    (asserts! (not is-claimed)
                        (err ERR-MILESTONE-ALREADY-CLAIMED)
                    )

                    ;; Mark as claimed
                    (map-set goal-milestones {
                        user: user,
                        milestone-id: milestone-id,
                    } {
                        percentage: (get percentage milestone-data),
                        target-amount: target-amount,
                        is-achieved: true,
                        is-claimed: true,
                        achievement-height: (get achievement-height milestone-data),
                    })

                    ;; Update goal rewards
                    (match (map-get? pension-goals user)
                        goal-data (map-set pension-goals user {
                            target-amount: (get target-amount goal-data),
                            current-progress: (get current-progress goal-data),
                            start-height: (get start-height goal-data),
                            target-height: (get target-height goal-data),
                            is-active: (get is-active goal-data),
                            total-rewards-earned: (+ (get total-rewards-earned goal-data) reward-amount),
                        })
                        true
                    )

                    ;; Update lifetime rewards
                    (match (map-get? goal-statistics user)
                        stats (map-set goal-statistics user {
                            total-goals-created: (get total-goals-created stats),
                            total-goals-completed: (get total-goals-completed stats),
                            total-milestones-achieved: (get total-milestones-achieved stats),
                            lifetime-rewards: (+ (get lifetime-rewards stats) reward-amount),
                        })
                        true
                    )

                    (ok reward-amount)
                )
            )
            (err ERR-GOAL-NOT-FOUND)
        )
    )
)

(define-public (deactivate-goal)
    (let ((user tx-sender))
        (match (map-get? pension-goals user)
            goal-data (begin
                (map-set pension-goals user {
                    target-amount: (get target-amount goal-data),
                    current-progress: (get current-progress goal-data),
                    start-height: (get start-height goal-data),
                    target-height: (get target-height goal-data),
                    is-active: false,
                    total-rewards-earned: (get total-rewards-earned goal-data),
                })
                (ok true)
            )
            (err ERR-GOAL-NOT-FOUND)
        )
    )
)

;; Goal Tracker Read-Only Functions

(define-read-only (get-pension-goal (user principal))
    (map-get? pension-goals user)
)

(define-read-only (get-goal-milestone
        (user principal)
        (milestone-id uint)
    )
    (map-get? goal-milestones {
        user: user,
        milestone-id: milestone-id,
    })
)

(define-read-only (get-goal-statistics (user principal))
    (map-get? goal-statistics user)
)

(define-read-only (get-goal-progress-percentage (user principal))
    (match (map-get? pension-goals user)
        goal-data (let (
                (current (get current-progress goal-data))
                (target (get target-amount goal-data))
            )
            (if (> target u0)
                (ok (/ (* current u100) target))
                (ok u0)
            )
        )
        (err ERR-GOAL-NOT-FOUND)
    )
)

(define-read-only (is-goal-expired (user principal))
    (match (map-get? pension-goals user)
        goal-data (ok (> burn-block-height (get target-height goal-data)))
        (err ERR-GOAL-NOT-FOUND)
    )
)

(define-read-only (get-milestone-count (user principal))
    (ok (default-to u0 (map-get? user-milestone-count user)))
)

(define-read-only (get-achievable-milestones (user principal))
    (match (map-get? pension-goals user)
        goal-data (let (
                (current-progress (get current-progress goal-data))
                (milestone-count (default-to u0 (map-get? user-milestone-count user)))
            )
            (ok (fold count-achievable-milestones
                (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9) {
                user: user,
                progress: current-progress,
                count: u0,
            }))
        )
        (err ERR-GOAL-NOT-FOUND)
    )
)

(define-private (count-achievable-milestones
        (milestone-id uint)
        (data {
            user: principal,
            progress: uint,
            count: uint,
        })
    )
    (let (
            (user (get user data))
            (progress (get progress data))
            (current-count (get count data))
        )
        (match (map-get? goal-milestones {
            user: user,
            milestone-id: milestone-id,
        })
            milestone-data (let (
                    (target (get target-amount milestone-data))
                    (is-achieved (get is-achieved milestone-data))
                )
                (if (and (>= progress target) (not is-achieved))
                    {
                        user: user,
                        progress: progress,
                        count: (+ current-count u1),
                    }
                    {
                        user: user,
                        progress: progress,
                        count: current-count,
                    }
                )
            )
            {
                user: user,
                progress: progress,
                count: current-count,
            }
        )
    )
)

(define-constant MAX-KEEPER-REWARD-BPS u200)
(define-constant ERR-KEEPER-NOT-ENROLLED u300)
(define-constant ERR-INVALID-KEEPER-REWARD u301)
(define-constant ERR-KEEPER-UNAUTHORIZED u302)
(define-constant ERR-NO-KEEPER u303)
(define-map keepers
    principal
    {
        keeper: principal,
        reward-bps: uint,
    }
)
(define-read-only (get-keeper (owner principal))
    (map-get? keepers owner)
)
(define-public (set-keeper
        (keeper principal)
        (reward-bps uint)
    )
    (match (map-get? users tx-sender)
        user-data (begin
            (asserts! (<= reward-bps MAX-KEEPER-REWARD-BPS)
                (err ERR-INVALID-KEEPER-REWARD)
            )
            (map-set keepers tx-sender {
                keeper: keeper,
                reward-bps: reward-bps,
            })
            (ok keeper)
        )
        (err ERR-KEEPER-NOT-ENROLLED)
    )
)
(define-public (revoke-keeper)
    (if (is-some (map-get? keepers tx-sender))
        (begin
            (map-delete keepers tx-sender)
            (ok true)
        )
        (err ERR-NO-KEEPER)
    )
)
(define-public (keeper-ping (owner principal))
    (match (map-get? keepers owner)
        kdata (match (map-get? users owner)
            user-data (let (
                    (balance (get balance user-data))
                    (bps (get reward-bps kdata))
                    (reward (/ (* balance bps) MAX-BPS))
                    (new-balance (- balance reward))
                )
                (begin
                    (asserts! (is-eq tx-sender (get keeper kdata))
                        (err ERR-KEEPER-UNAUTHORIZED)
                    )
                    (map-set users owner {
                        balance: new-balance,
                        start-height: (get start-height user-data),
                        retirement-age: (get retirement-age user-data),
                        last-activity: burn-block-height,
                    })
                    (if (> reward u0)
                        (begin
                            (try! (stx-transfer? reward (as-contract tx-sender)
                                tx-sender
                            ))
                            (ok reward)
                        )
                        (ok u0)
                    )
                )
            )
            (err ERR-KEEPER-NOT-ENROLLED)
        )
        (err ERR-NO-KEEPER)
    )
)
