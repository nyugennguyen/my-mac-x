# Threat Model — Sprint 0

## 1. Phạm vi và posture

Threat model bao phủ app menu bar My Mac X, Accessibility control, global input/hotkey path, overlays, local configuration/diagnostics và pipeline phát hành direct distribution. Không bao phủ cloud/account vì v1 local-first và không có backend.

Security posture mặc định:

- Chỉ yêu cầu quyền tối thiểu cần cho feature đã ship.
- Fail closed khi permission/capability không rõ.
- Không dùng private API trong production.
- Không thu telemetry; diagnostics do người dùng chủ động copy sau redaction.
- Không lưu nội dung phím, title/document content, clipboard hoặc screen capture.

Scope/release tổng thể: [Project Plan — quyết định nền tảng](../../my-mac-x_projectplan.md#1-tóm-tắt-quyết-định) và [test/release gates](../../my-mac-x_projectplan.md#10-test-strategy).

## 2. Assets cần bảo vệ

| ID | Asset | Yêu cầu bảo vệ |
|---|---|---|
| A-01 | Keyboard input của người dùng | Không capture ngoài scope; không lưu/log/exfiltrate; không làm mất/sticky input |
| A-02 | Quyền Accessibility/Input Monitoring | Không lạm dụng; giải thích đúng; nhận biết revoked; least privilege |
| A-03 | Cửa sổ và vị trí/size hiện tại | Không mutate sai target; Undo; không làm window off-screen |
| A-04 | Focus/active application | Overlay/HUD không chiếm focus trái ý người dùng |
| A-05 | Local config/hotkey/profile/history | Integrity, schema validation, safe migration; không chứa dữ liệu nội dung |
| A-06 | Diagnostics/logs | Redaction; bounded retention; user-mediated export |
| A-07 | Update/release artifact | Authenticity, integrity, notarization, rollback |
| A-08 | App identity/bundle/signing credentials | Không rò rỉ credential; entitlement được review |
| A-09 | User trust/consent | Prompt đúng lúc; không xin quyền không cần; trạng thái quyền minh bạch |

## 3. Data inventory

| Dữ liệu | Mục đích | Lưu? | Retention đề xuất | Cho phép trong diagnostics? |
|---|---|---|---|---|
| Action ID/layout ID | Thực thi, debug | Config/history cục bộ nếu cần | Bounded; history theo window session | Có |
| Hotkey chord cấu hình | Register hotkey | Có, local config | Đến khi user đổi/reset | Có |
| Prefix state/key event tạm thời | Super Mode state machine | RAM trong armed session | Xóa ngay success/cancel/timeout | Chỉ outcome/code, không raw key stream |
| Window identity kỹ thuật | Target/Undo | RAM hoặc bounded history | Không vượt session nếu chưa chứng minh cần persist | Chỉ hash/non-content ID nếu cần |
| Window frame/display ID | Layout/Undo/profile | Local config/history | Bounded | Có, nếu không suy ra nội dung |
| Permission/capability/error code | Health/diagnostics | Local bounded logs | `[TBD qua policy]` | Có |
| Window title/document path/content | Không cần | **Không** | 0 | **Không** |
| Clipboard/screenshot/screen pixels | Không cần | **Không** | 0 | **Không** |
| Raw keystroke stream | Không cần | **Không** | 0 | **Không** |
| Account/device advertising ID/telemetry | Không thuộc v1 | **Không** | 0 | **Không** |

## 4. Trust boundaries và data flows

```text
[Người dùng]
   │ consent / drag / hotkey
   ▼
┌──────────────── My Mac X process ────────────────┐
│ Input adapter → Action registry → Window engine  │
│ UI/Overlay   ↔ Settings store  ↔ Diagnostics     │
└──────┬──────────────┬───────────────┬────────────┘
       │ TB-01        │ TB-02         │ TB-03
       ▼              ▼               ▼
 macOS Event/AX    AppKit/Displays   Local filesystem
 APIs & TCC        & WindowServer    config/logs
       │ TB-04
       ▼
 External app processes/windows

[Build/Release] ── TB-05 ──> Signed + notarized artifact ──> User device
```

| Boundary | Rủi ro chính | Control yêu cầu |
|---|---|---|
| TB-01 App ↔ TCC/Event Tap/AX | Quyền rộng, event injection/capture, revoked mid-action | Preflight runtime, least privilege, bounded tap callback, fail closed |
| TB-02 App ↔ WindowServer/displays | Sai coordinate/focus/off-screen, lifecycle race | Geometry normalization, read-back, clamp, observer cleanup |
| TB-03 App ↔ filesystem | Config tamper/corrupt, sensitive logs | Schema validation, atomic write, permissions mặc định, redaction |
| TB-04 App ↔ external apps | AX target spoof/stale reference/hung app | Revalidate PID/window/capability, bounded timeout/retry, no title dependency |
| TB-05 Build/release ↔ user | Supply-chain/tampered update/signing misuse | Locked CI, code signing, notarization, hash/signature verification, rollback |

## 5. Threats, mitigations và residual risk

| ID | Threat / abuse case | Mức | Mitigation bắt buộc | Verification | Residual risk / disposition |
|---|---|---:|---|---|---|
| T-01 | Global input path vô tình ghi/log raw keystrokes | Critical | Callback chỉ map chord/state; cấm log raw event; ephemeral buffer; code review input call sites | Unit log sink + privacy review + P0-04 | OS/API vẫn đưa event cho process; giảm bằng code scope và review. Owner: Input/Security |
| T-02 | Super Mode nuốt phím hoặc modifier sau timeout/crash/tap disabled | High | Explicit state machine; deadline; cancel path; tap-disable recovery; không suppress ngoài armed/recognized sequence | P0-04 cases success/Esc/timeout/invalid/disable | Process crash trong suppression window có thể ảnh hưởng event hiện tại; chấp nhận nếu chỉ bounded single event |
| T-03 | AX mutate nhầm window do focus race/stale reference | High | Snapshot identity + revalidate PID/role/capability ngay trước mutation; serialize action; read-back; Undo | P0-03 race tests + integration | Public identity có thể không ổn định `[PoC U-06]`; fail closed khi mismatch |
| T-04 | Window bị đẩy off-screen do coordinate/display disconnect | High | Normalize/clamp visibleFrame; react screen-change; cancel overlay; recovery layout | P0-05 + CF-03 | OS/external app minimum size có thể vượt frame; feedback + best-visible placement |
| T-05 | Overlay/HUD chiếm focus hoặc che UI nhạy cảm | Medium | Non-activating panel, no key/main by default, bounded lifetime, user cancel | P0-05 focus trace + UX audit | VoiceOver/keyboard access có thể xung đột `[Research]`; cần interaction-mode decision |
| T-06 | App xin thêm Input Monitoring/Screen Recording không cần thiết | High | Permission inventory; runtime preflight trước prompt; Screen Recording forbidden in v1; release entitlement review | Clean-machine permission matrix | Requirement Event Tap chưa chốt `[PoC P0-04]` |
| T-07 | Diagnostics làm lộ title/path/key/window content | High | Allowlist fields; structured error codes; redact/free-text avoidance; user-mediated copy | Golden log tests + manual review | OS error description có thể chứa dữ liệu; không export raw OS description |
| T-08 | Config import tampered/corrupt gây crash hoặc command injection | High | Strict versioned schema, size/depth limits, reject unknown dangerous action IDs, no executable content, atomic backup | Fuzz/schema tests | Import thuộc v1; format chưa chốt `[Research]` |
| T-09 | Malicious/buggy app làm AX call hang hoặc trả dữ liệu bất thường | High | Callback nhẹ; timeout/bounded retry; validate types/ranges; isolate error | Fault injection + app compatibility | AX call cancellation semantics cần `[PoC P0-03]`; degraded mode có thể cần thiết |
| T-10 | Private API làm vỡ security/release compatibility | High | CI/static scan; architecture rule; no SkyLight/private symbol in production target | TM-G06 + binary inspection | Experimental branch vẫn có risk; không link/copy vào release target |
| T-11 | Tampered update hoặc signing credential compromise | Critical | Developer ID/notarization; updater signature validation nếu thêm updater; secret chỉ trong protected CI; rollback | Clean-machine Gatekeeper + release audit | Update mechanism chưa quyết định; manual channel vẫn có phishing risk |
| T-12 | Duplicate event tap/observer sau sleep/wake tạo action lặp | Medium | Single-owner lifecycle, idempotent register, cleanup, health state | Soak sleep/wake/fast-user-switch | OS lifecycle edge cases; monitor beta diagnostics bằng local counters |
| T-13 | Hotkey conflict với system/app shortcut gây unexpected action | Medium | Conflict detection, protected shortcut denylist/research, confirm replace, easy pause/reset | Recorder tests + manual shortcut matrix | Không thể biết mọi app-local shortcut; inform user và reversible config |
| T-14 | Local config/history bị app khác cùng user sửa | Medium | User-only permissions, schema/MAC decision research, validate on every load, safe reset | Tamper tests | Không chống được attacker đã chiếm user account; out of scope |
| T-15 | Accessibility app bị coi như keylogger/mất user trust | High | Just-in-time explanation, exact data policy, visible pause/health state, no network/telemetry | UX sign-off + binary/network audit | Quyền Accessibility vốn rộng; residual risk phải được privacy docs nói rõ |

## 6. Security gates

| Gate | Điều kiện Pass | Giai đoạn | Evidence | Status |
|---|---|---|---|---|
| TM-G01 Permission minimum | Danh sách permission/entitlement đã test; không Screen Recording; Input Monitoring chỉ nếu P0-04 chứng minh cần | G0 | P0-04 + entitlement inventory | ☐ |
| TM-G02 Input safety | Success/Esc/timeout/invalid/tap-disabled không để state armed hoặc mất modifier | G0/G5 | P0-04 + state tests | ☐ |
| TM-G03 AX target safety | Revalidation/read-back/bounded retry strategy khả thi trên 6 app | G0/G2 | P0-03 + integration tests | ☐ |
| TM-G04 Data minimization | Data inventory được Product/Security duyệt; forbidden fields absent trong logs/config | G0/G1 | log/config audit | ☐ |
| TM-G05 Overlay focus | Chooser/HUD không lấy focus ở supported flows | G0/G4 | P0-05/manual matrix | ☐ |
| TM-G06 Public API only | Production binary/source scan không có SkyLight/private API | Mọi release | scan + architecture review | ☐ |
| TM-G07 Config integrity | Parser versioned, bounded, validation/fuzz pass; corrupt config safe reset/backup | G6 | tests | ☐ |
| TM-G08 Lifecycle safety | Sleep/wake/display change/permission revoke không duplicate tap/observer hay retry loop | G5/G7 | soak report | ☐ |
| TM-G09 Supply chain | Signed/notarized artifact; credentials không ở repo/log; Gatekeeper máy sạch pass | G7 | release report | ☐ |
| TM-G10 Residual risk acceptance | Mọi High/Critical residual risk có owner, disposition và sign-off | G0 + release | risk register | ☐ |

Không được qua G0 nếu TM-G01…TM-G05 hoặc TM-G10 chưa có kết luận. Có thể `Conditional Pass` chỉ khi unknown có owner, timebox và feature flag/fail-closed plan.

## 7. Factual unknowns / research log

| ID | Câu hỏi cần bằng chứng | Phương pháp | Blocking |
|---|---|---|---|
| SEC-U01 | Event Tap configuration thực tế có cần Input Monitoring trên macOS 14+ và hardened/notarized build không? | P0-04 trên user profile sạch + signed PoC; đối chiếu Apple docs | G0/TM-G01 |
| SEC-U02 | App Sandbox có khả thi với toàn bộ AX/Event Tap scope hay direct Developer ID phải unsandboxed? | Apple primary-source research + entitlement spike | Distribution decision |
| SEC-U03 | AX calls có timeout/cancellation behavior nào khi target app hung? | P0-03 fault injection; không giả định API cancel được | Window engine design |
| SEC-U04 | Window identity nào đủ để chống focus race mà không đọc title? | P0-03 prototype trên multi-window apps | TM-G03 |
| SEC-U05 | VoiceOver với non-activating HUD/chooser cần focus mode riêng không? | Accessibility UX PoC | UX/security balance |
| SEC-U06 | Updater nào (nếu có) và signature/rollback model ra sao? | Release research sau quyết định D-03 | G7, không block G0 |

## 8. Residual risk acceptance

| Risk ID | Owner | Quyết định | Điều kiện/feature flag | Người duyệt/ngày |
|---|---|---|---|---|
| `[TBD]` | `[TBD]` | ☐ Accept ☐ Mitigate ☐ Remove scope | `[TBD]` | `[TBD]` |

## 9. Sign-off

- Security reviewer: `[TBD]` — `☐ Approved ☐ Conditional ☐ Rejected` — `[date]`
- Tech lead: `[TBD]` — `☐ Approved ☐ Changes requested` — `[date]`
- Product owner (privacy/consent): `[TBD]` — `☐ Approved ☐ Changes requested` — `[date]`

