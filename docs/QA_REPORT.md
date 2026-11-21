# QA Test Report — StreakSave (UniHack 2026)

## 1. Test Environment
* **Project:** StreakSave (`0NguyenNgan0/streaksave-avalanche`)
* **Branch Tested:** `dev`
* **Network:** Avalanche Fuji Testnet (`Chain ID: 43113`)
* **Frontend URL:** `http://localhost:3000`
* **Wallet Used:** Core Wallet (`0x53F0...D574 · Fuji`, Fresh / Test Wallet)
* **QA & Integration Lead:** Lương Thị Thu Huyền
* **Test Date:** 21/11/2026

### Deployed Contracts (Fuji Testnet)
* **StreakSavings:** `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9`
* **MockUSDC:** `0x1aaB5693678b18753dCFD5096f497031c1A1f126`

---

## 2. End-to-End Functional Test Cases

| TC ID | Test Flow / Scenario | Expected Result | Status | Evidence / Notes |
| :--- | :--- | :--- | :---: | :--- |
| **TC-01** | **Wallet Connection & Fuji Network** | Connect Core Wallet on Avalanche Fuji Testnet (`43113`); read on-chain state cleanly | `PASS` | `0x53F0...D574 · Fuji` connected; on-chain data synced |
| **TC-02** | **Approve MockUSDC (Step 1/2)** | Core Wallet prompts spend limit approval for `StreakSavings`; transaction confirms | `PASS` | Verified on `/deposit` (`5 USDC` approve flow) |
| **TC-03** | **Deposit & Streak Update (Step 2/2)** | Deposit succeeds; wallet `MockUSDC` decreases by deposited amount and dashboard updates | `PASS` | Wallet balance updated from `66 USDC` to `61 USDC` after `5 USDC` deposit |
| **TC-04** | **Claim Rewards & Withdraw** | Claim rewards and withdraw principal execute cleanly without state lock or balance error | `PASS` | Verified in E2E run on Fuji Testnet |

---

## 3. Fresh Wallet & Edge Case Testing

| Case ID | Edge Case | Scenario Tested | Expected Behavior | Status | Evidence / Observed Behavior |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **EC-01** | **Double Action** | Rapid click / repeated click while `Approve` transaction is in progress | Button locks (`Đang approve...` / `Đang xử lý giao dịch...`) and prevents duplicate submission | `PASS` | Button blocked extra clicks while Core Wallet approval prompt was open |
| **EC-02** | **Reject Tx** | Click `Reject` on Core Wallet prompt during `Approve` | Button unlocks back to `Bước 1: Approve 5 USDC`; clear message shown; balance unchanged | `PASS` | Displays `Giao dịch chưa hoàn tất — User rejected the request.`; balance stays `66 USDC` |
| **EC-03** | **Insufficient Balance** | Enter amount (`100`) greater than available wallet balance (`66 USDC`) | Warning shown and action button disabled to prevent invalid submission | `PASS` | Displays `Số tiền vượt quá số dư khả dụng.` and disables approve button |
| **EC-04** | **Reset Streak** | Observe streak counter across epoch transition (`Epoch #1625` -> `Epoch #1626`) | Streak resets to `0 epoch` when not maintained in the new epoch while principal stays safe | `PASS` | Changed from `1 epoch` (`✓ Đang duy trì`) at `Epoch #1625` to `0 epoch` at `Epoch #1626`; `61 USDC` wallet balance intact |

---

## 4. Summary & Release Readiness
* **Core E2E Flows:** 4 / 4 `PASS`
* **Edge Cases:** 4 / 4 `PASS`
* **Blocking / Critical Bugs:** 0
* **Conclusion:** Core flows and edge cases on `dev` against Avalanche Fuji Testnet (`Chain ID: 43113`) are verified and ready for `main` merge and demo preparation.
