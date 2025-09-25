;; SecureGuard - Smart Contract Security Auditing Platform
;; A decentralized security auditing platform for Clarity smart contracts

;; Constants
(define-constant PLATFORM_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_AUDITOR (err u103))

;; Data Variables
(define-data-var audit-counter uint u0)
(define-data-var service-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map security-audits
    { audit-id: uint }
    {
        target-contract: principal,
        auditor: principal,
        block-height: uint,
        risk-level: uint,
        issues-detected: uint,
        report-hash: (string-ascii 64),
        is-validated: bool
    }
)

(define-map certified-auditors
    { auditor-address: principal }
    {
        credibility-rating: uint,
        completed-audits: uint,
        validated-audits: uint,
        status-active: bool
    }
)

(define-map contract-reports
    { target-contract: principal }
    {
        most-recent-audit: uint,
        audit-history-count: uint,
        highest-security-rating: uint
    }
)

;; Authorization map for trusted auditors
(define-map trusted-validators principal bool)

;; Public Functions

;; Register a new security auditor
(define-public (register-auditor)
    (let ((caller tx-sender))
        (asserts! (is-none (map-get? certified-auditors { auditor-address: caller })) ERR_ALREADY_EXISTS)
        (map-set certified-auditors 
            { auditor-address: caller }
            {
                credibility-rating: u0,
                completed-audits: u0,
                validated-audits: u0,
                status-active: true
            }
        )
        (ok true)
    )
)

;; Submit a security audit result
(define-public (submit-audit (target-contract principal) (risk-level uint) (issues-detected uint) (report-hash (string-ascii 64)))
    (let (
        (caller tx-sender)
        (new-audit-id (+ (var-get audit-counter) u1))
        (auditor-info (unwrap! (map-get? certified-auditors { auditor-address: caller }) ERR_INVALID_AUDITOR))
    )
        ;; Ensure auditor is registered and active
        (asserts! (get status-active auditor-info) ERR_INVALID_AUDITOR)
        
        ;; Pay service fee
        (try! (stx-transfer? (var-get service-fee) caller PLATFORM_OWNER))
        
        ;; Create audit record
        (map-set security-audits
            { audit-id: new-audit-id }
            {
                target-contract: target-contract,
                auditor: caller,
                block-height: stacks-block-height,
                risk-level: risk-level,
                issues-detected: issues-detected,
                report-hash: report-hash,
                is-validated: false
            }
        )
        
        ;; Update auditor statistics
        (map-set certified-auditors
            { auditor-address: caller }
            (merge auditor-info { completed-audits: (+ (get completed-audits auditor-info) u1) })
        )
        
        ;; Update contract audit tracking
        (let ((contract-info (default-to 
                { most-recent-audit: u0, audit-history-count: u0, highest-security-rating: u100 }
                (map-get? contract-reports { target-contract: target-contract })
            )))
            (map-set contract-reports
                { target-contract: target-contract }
                {
                    most-recent-audit: new-audit-id,
                    audit-history-count: (+ (get audit-history-count contract-info) u1),
                    highest-security-rating: (if (< risk-level (get highest-security-rating contract-info)) 
                                   risk-level 
                                   (get highest-security-rating contract-info))
                }
            )
        )
        
        ;; Update audit counter
        (var-set audit-counter new-audit-id)
        
        (ok new-audit-id)
    )
)

;; Validate an audit (only trusted validators can validate others' audits)
(define-public (validate-audit (audit-id uint))
    (let (
        (caller tx-sender)
        (audit-info (unwrap! (map-get? security-audits { audit-id: audit-id }) ERR_NOT_FOUND))
        (original-auditor (get auditor audit-info))
    )
        ;; Ensure caller is trusted and not validating their own audit
        (asserts! (default-to false (map-get? trusted-validators caller)) ERR_UNAUTHORIZED)
        (asserts! (not (is-eq caller original-auditor)) ERR_UNAUTHORIZED)
        
        ;; Mark audit as validated
        (map-set security-audits
            { audit-id: audit-id }
            (merge audit-info { is-validated: true })
        )
        
        ;; Update original auditor's credibility
        (let ((auditor-info (unwrap! (map-get? certified-auditors { auditor-address: original-auditor }) ERR_NOT_FOUND)))
            (map-set certified-auditors
                { auditor-address: original-auditor }
                (merge auditor-info { 
                    validated-audits: (+ (get validated-audits auditor-info) u1),
                    credibility-rating: (+ (get credibility-rating auditor-info) u10)
                })
            )
        )
        
        (ok true)
    )
)

;; Admin function to authorize validators
(define-public (authorize-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender PLATFORM_OWNER) ERR_UNAUTHORIZED)
        (map-set trusted-validators validator true)
        (ok true)
    )
)

;; Admin function to set service fee
(define-public (update-service-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender PLATFORM_OWNER) ERR_UNAUTHORIZED)
        (var-set service-fee new-fee)
        (ok true)
    )
)

;; Read-only Functions

;; Get audit details
(define-read-only (get-audit-details (audit-id uint))
    (map-get? security-audits { audit-id: audit-id })
)

;; Get auditor details
(define-read-only (get-auditor-profile (auditor-address principal))
    (map-get? certified-auditors { auditor-address: auditor-address })
)

;; Get contract audit summary
(define-read-only (get-contract-security-report (target-contract principal))
    (map-get? contract-reports { target-contract: target-contract })
)

;; Get latest audit for a contract
(define-read-only (get-most-recent-audit (target-contract principal))
    (let ((contract-info (map-get? contract-reports { target-contract: target-contract })))
        (match contract-info
            summary (map-get? security-audits { audit-id: (get most-recent-audit summary) })
            none
        )
    )
)

;; Get current audit counter
(define-read-only (get-total-audits)
    (var-get audit-counter)
)

;; Get service fee
(define-read-only (get-current-service-fee)
    (var-get service-fee)
)

;; Check if validator is trusted
(define-read-only (is-trusted-validator (validator principal))
    (default-to false (map-get? trusted-validators validator))
)