# Nghiên cứu khả thi API quản lý cửa sổ macOS

Ngày xác minh: 2026-08-23  
Phạm vi: Sprint 0 của My Mac X, target đề xuất macOS 14 trở lên  
Nguồn: tài liệu và hướng dẫn chính thức của Apple; diễn đàn chỉ được dùng khi câu trả lời đến từ Apple Developer Technical Support (DTS).

## Cách đọc mức độ chắc chắn

- **FACT** — hành vi hoặc contract được Apple công bố trực tiếp.
- **INFERENCE** — kết luận kỹ thuật suy ra từ các public API đã công bố; cần xác nhận bằng spike trên máy thật.
- **UNKNOWN** — Apple không công bố đủ contract để coi hành vi là ổn định.

## Kết luận cho Gate G0

| Hạng mục | Kết luận | Public API | Quyết định đề xuất |
|---|---|---:|---|
| Lấy cửa sổ đang focus của app khác | Khả thi khi người dùng cấp Accessibility | Có | Tiếp tục P0-03 |
| Đọc/ghi vị trí và kích thước | Khả thi, nhưng từng cửa sổ có thể không hỗ trợ hoặc tạm thời không phản hồi | Có | Bọc bằng capability check, typed error và read-back |
| Hotkey toàn cục | Khả thi | Có | Dùng cơ chế hotkey đơn giản cho chord; chỉ dùng Event Tap khi cần prefix/suppression |
| Super/prefix mode và nuốt phím | Khả thi về API; hành vi permission hiện đại cần spike sạch | Có | Event Tap callback cực nhẹ, có recovery; test Accessibility/Input Monitoring riêng |
| Hình học Notch và nhiều màn hình | Khả thi để tạo vùng kích hoạt/overlay | Có | Dùng `NSScreen`; không hard-code model hoặc kích thước Notch |
| Launch at Login | Khả thi từ macOS 13 | Có | `SMAppService.mainApp` |
| Phân phối | Core feature không phù hợp App Sandbox | Có đường direct | Developer ID + Hardened Runtime + notarization |
| Chuyển cửa sổ app khác sang Space/Desktop bất kỳ | Không tìm thấy public API đáp ứng | Không | Không thuộc v1; tuyệt đối không ship SkyLight/private symbols |

**Khuyến nghị Go cho Sprint 0:** tiếp tục xây prototype bằng public API. Gate G0 chỉ được coi là đạt sau khi P0-03/P0-04/P0-05 chạy trên máy thật với quyền được cấp từ một trạng thái TCC sạch. Spaces giữ ngoài v1 đúng như ADR hiện tại.

---

## 1. Accessibility: focused window và move/resize

### 1.1 Permission và trạng thái trust

**FACT.** `AXIsProcessTrustedWithOptions` trả về việc process hiện tại có phải Accessibility client được tin cậy hay không. Khi truyền `kAXTrustedCheckOptionPrompt: true`, hệ thống có thể thông báo người dùng; prompt diễn ra bất đồng bộ và **không thay đổi return value của lần gọi hiện tại**. Vì vậy không được coi `true` trong options là “xin quyền xong”, cũng không được block chờ hàm này trả về quyền mới. Nguồn: [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

**INFERENCE.** Permission manager nên có các trạng thái tối thiểu `unknown`, `notGranted`, `promptRequested`, `granted`, `revoked`. Sau khi request, app re-check khi trở lại active và trước mỗi phiên thao tác; không polling nhanh liên tục.

**UNKNOWN.** Apple không công bố trong tài liệu symbol này thời gian prompt xuất hiện, việc prompt có hiện lại sau khi người dùng từ chối, hay một public API chuyên biệt để mở thẳng đúng pane Accessibility. UI onboarding phải chịu được việc người dùng tự mở System Settings và quay lại sau.

### 1.2 Cách tìm focused window

**FACT.** `AXUIElementCreateSystemWide()` tạo accessibility object cấp hệ thống và được Apple mô tả là hữu ích để tìm focused accessibility object bất kể app nào đang active. `kAXFocusedApplicationAttribute` trên system-wide element trả về app đang nhận keyboard input. Trên application element, `kAXFocusedWindowAttribute` biểu diễn cửa sổ đang focus của app đó. Nguồn: [AXUIElementCreateSystemWide](https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide), [kAXFocusedApplicationAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedapplicationattribute), [kAXFocusedWindowAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute).

Luồng public API đề xuất:

```text
AXUIElementCreateSystemWide()
  -> AXFocusedApplication
  -> AXFocusedWindow
  -> kiểm tra role/capability
  -> đọc AXPosition + AXSize
```

Một đường thay thế hợp lệ là lấy PID của frontmost `NSRunningApplication`, tạo application element bằng `AXUIElementCreateApplication(pid)`, rồi đọc `AXFocusedWindow`. Nên giữ đường này như fallback có kiểm thử, không ghép logic PID/AppKit vào geometry engine.

**FACT.** `kAXWindowsAttribute` là mảng accessibility object đại diện các cửa sổ của một app. Đây là fallback phù hợp khi focused-window attribute không có giá trị, nhưng “window đầu tiên” không đồng nghĩa với “cửa sổ người dùng muốn thao tác”. Nguồn: [kAXWindowsAttribute](https://developer.apple.com/documentation/applicationservices/kaxwindowsattribute).

### 1.3 Đọc và ghi position/size

**FACT.** `AXUIElementCopyAttributeValue` đọc giá trị attribute. `kAXPositionAttribute` là tọa độ global của góc trên-trái; `(0, 0)` nằm ở góc trên-trái của màn hình có menu bar. `kAXSizeAttribute` là chiều ngang và dọc của accessibility object. `CGPoint` và `CGSize` được bọc/mở bằng `AXValueCreate` và `AXValueGetValue`. Nguồn: [AXUIElement API](https://developer.apple.com/documentation/applicationservices/axuielement), [kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute), [kAXSizeAttribute](https://developer.apple.com/documentation/applicationservices/kaxsizeattribute), [AXValueType](https://developer.apple.com/documentation/applicationservices/axvaluetype), [AXValueCreate](https://developer.apple.com/documentation/applicationservices/1459351-axvaluecreate).

**FACT.** `AXUIElementIsAttributeSettable` cho biết một attribute cụ thể có thể ghi hay không. `AXUIElementSetAttributeValue` thực hiện ghi và có thể trả về ít nhất các lỗi `illegalArgument`, `attributeUnsupported`, `invalidUIElement`, `cannotComplete`, `notImplemented`. Nguồn: [AXUIElement API](https://developer.apple.com/documentation/applicationservices/axuielement), [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue).

**INFERENCE.** Mutation pipeline an toàn nên:

1. Xác minh reference còn hợp lệ và cả `AXPosition`/`AXSize` đều settable.
2. Chụp frame cũ cho Undo.
3. Set position và size bằng một ordering có thể cấu hình; một số app có thể clamp sau lần set đầu.
4. Đọc lại cả hai attribute và so sánh với target theo tolerance bằng point.
5. Nếu sai khác, retry hữu hạn theo ordering còn lại; không loop vô hạn.
6. Trả typed result gồm requested frame, observed frame và AX error.

**UNKNOWN.** Apple không bảo đảm mọi app/cửa sổ hỗ trợ ghi hai attribute, không bảo đảm thao tác position+size là atomic, và không công bố ordering chung cho mọi framework UI. Finder, Safari, Terminal, Xcode, Chrome và một app Electron phải được kiểm thử riêng; sheet, dialog, cửa sổ không resizable, minimized và native full-screen phải có kết quả “unsupported” an toàn thay vì cố ép frame.

### 1.4 Hai hệ tọa độ phải được tách thành module

**FACT.** Accessibility dùng gốc trên-trái cho `AXPosition`. Cocoa/AppKit mặc định dùng screen coordinates với gốc ở dưới-trái màn hình primary; trong cấu hình desktop liền nhau, các màn hình khác có origin offset và có thể nằm ở phía bất kỳ. Đơn vị user space là point, không nên giả định một point bằng một pixel. Nguồn: [kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute), [Cocoa Drawing Guide — Coordinate Systems and Transforms](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html).

**INFERENCE.** Cần một `CoordinateConverter` duy nhất giữa AX global top-left và AppKit global bottom-left. Không chuyển đổi bằng riêng chiều cao của màn hình chứa window; công thức phải dựa trên desktop global reference và phải có fixtures cho external display ở trái/trên/dưới, origin âm, mirror mode và mixed scaling.

**Quyết định:** public API, production-safe. Không để SwiftUI view, hotkey handler hay overlay tự làm phép đổi trục.

---

## 2. CGEventTap: permission, callback và recovery

### 2.1 Chọn loại tap

**FACT.** `CGEventTapCreate` nhận vị trí tap, placement, option passive/active, event mask và callback. Nếu process không được phép theo dõi một số event, hệ thống loại các bit đó khỏi mask; nếu mask rỗng, hàm trả `NULL`. HID-entry tap chỉ dành cho process root, nên app người dùng thông thường không được chọn điểm đó. Nguồn: [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29).

**FACT.** `.listenOnly` là passive listener. Với active filter, callback có thể trả event gốc, event đã sửa/thay thế, hoặc `NULL` để xóa event; với passive listener, return value không ảnh hưởng event stream. Nguồn: [CGEventTapOptions.listenOnly](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly), [CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback).

**Quyết định đề xuất:**

- Dùng cơ chế đăng ký global hotkey/chord riêng cho action một bước nếu nó đáp ứng yêu cầu; không bật event stream listener chỉ để bắt các chord cố định.
- Dùng session event tap `.listenOnly` cho spike quan sát chuỗi phím.
- Chỉ dùng active filter khi Super Mode thực sự cần swallow phím sau prefix; ngoài state “armed”, trả nguyên event ngay.
- Không dùng HID event tap và không yêu cầu root.

### 2.2 Input Monitoring và Accessibility

**FACT.** Core Graphics có `CGPreflightListenEventAccess()` để kiểm tra và `CGRequestListenEventAccess()` để yêu cầu quyền listen-event. Apple DTS xác nhận `CGEventTap` listen-only dựa vào Input Monitoring và cơ chế này có thể dùng trong sandbox, khác với Accessibility privilege mà một số global event monitor cũ sử dụng. Nguồn: [Core Graphics functions](https://developer.apple.com/documentation/coregraphics/core-graphics-functions), [Apple DTS — Accessibility permission in sandboxed app](https://developer.apple.com/forums/thread/707680), [Apple DTS — global monitor và CGEventTap](https://developer.apple.com/forums/thread/811443).

**FACT.** My Mac X vẫn cần Accessibility trust độc lập để điều khiển cửa sổ app khác; Input Monitoring không thay thế AX permission. Apple cũng ghi rõ event tap nhận key-up/key-down khi process có assistive-device access trong contract của `CGEventTapCreate`. Nguồn: [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29), [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

**UNKNOWN.** Tài liệu symbol công khai không mô tả đầy đủ ma trận TCC hiện đại cho mọi tổ hợp `tap location × listenOnly/defaultTap × event type × sandbox`. Đặc biệt cần xác minh active filter/swallow trên macOS 14, 15 và 26 từ user account sạch. Không suy luận “Accessibility đã cấp thì Input Monitoring chắc chắn đã cấp”, hoặc ngược lại.

**Spike bắt buộc P0-04:** thử fresh install, deny, grant, revoke-runtime cho hai quyền; log chỉ trạng thái/quyền và error, tuyệt đối không log ký tự hay key stream.

### 2.3 Callback bị disable và cách phục hồi

**FACT.** Core Graphics gửi loại event `tapDisabledByTimeout` khi tap bị tắt do timeout và `tapDisabledByUserInput` khi bị tắt do user input. `CGEventTapEnable(tap, true)` có thể bật lại một tap đã bị disable vì không phản hồi hoặc do người dùng yêu cầu. Nguồn: [CGEventType.tapDisabledByTimeout](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout), [CGEventType.tapDisabledByUserInput](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbyuserinput), [CGEventTapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable%28tap%3Aenable%3A%29).

**FACT.** Callback chạy theo run loop mà tap được gắn vào; active filter được phép xóa hoặc thay đổi event. Nguồn: [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29), [CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback).

**INFERENCE.** Callback phải chỉ parse dữ liệu tối thiểu, cập nhật state nhỏ và enqueue action. Không gọi AX, không I/O, không serialize config và không log đồng bộ trong callback. Khi nhận hai disabled event, reset Super Mode về idle trước, re-enable tap, rồi phát health event ra ngoài callback. Cần metric đếm disable/re-enable nhưng không chứa phím.

**Quyết định:** public API, production-safe nếu callback bounded và có lifecycle cho sleep/wake, permission revoke, run-loop teardown và duplicate-start.

---

## 3. `NSScreen`, Notch và thay đổi display

### 3.1 Các rectangle chính thức

**FACT.** `NSScreen.frame` mô tả kích thước/vị trí màn hình. `visibleFrame` là phần hiện tại an toàn để vẽ, không gồm vùng Dock và menu bar; trên Mac có camera housing, nó cũng không gồm bezel hoặc các vùng hiển thị hai bên bezel. Apple cảnh báo không cache `visibleFrame` vì UI settings có thể thay đổi giữa các lần gọi. Nguồn: [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen), [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe).

**FACT.** `safeAreaInsets` cho khoảng cách từ các cạnh màn hình tới vùng nội dung không bị che. Trên một số Mac, top inset phản ánh camera housing; với system full-screen, AppKit tự đặt content trong safe area. Nguồn: [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets).

**FACT.** Khi top safe-area inset khác zero, `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` trả các vùng top-left/top-right không bị che, bằng global screen coordinates và nằm ngoài safe area; nếu top không bị che, giá trị là `nil` trong Swift. Nguồn: [NSScreen.auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc), [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen).

### 3.2 Xác định trigger và anchor cho Notch

**INFERENCE.** AppKit không công bố một property tên “notch rectangle”. Vùng che có thể suy ra có điều kiện từ khoảng trống giữa `auxiliaryTopLeftArea.maxX` và `auxiliaryTopRightArea.minX`, kết hợp `frame.maxY` và `safeAreaInsets.top`. Đây là derived geometry, không phải contract rằng khoảng trống luôn đúng bằng phần cứng Notch trong mọi display mode.

Thuật toán production đề xuất:

1. Xác định `NSScreen` chứa pointer hiện tại; không dùng `NSScreen.main` làm proxy cho màn hình đang kéo.
2. Đọc mới `frame`, `visibleFrame`, `safeAreaInsets` và auxiliary areas tại đầu drag session và khi nhận display-change.
3. Nếu hai auxiliary areas hợp lệ và tạo một center gap, dùng center gap làm vùng trigger; anchor panel ngay dưới vùng top obstruction/menu bar nhưng clamp toàn bộ panel trong usable bounds.
4. Nếu không có center gap, dùng top-center fallback với width/dwell cấu hình được.
5. Target frame cho cửa sổ luôn tính từ `visibleFrame`, không từ raw `frame`, trừ action được định nghĩa rõ là native full-screen.

**UNKNOWN.** Cần spike trên MacBook Notch thật để xác minh rectangle trong desktop thường, menu bar auto-hide, app full-screen, “Displays have separate Spaces”, Stage Manager và external display nằm phía trên primary. Cũng cần xác minh overlay dưới Notch không nhận key/main focus và không kích hoạt lại chính app My Mac X.

### 3.3 Display attach/detach/reconfigure

**FACT.** `NSApplication.didChangeScreenParametersNotification` được post khi cấu hình display thay đổi, từ thao tác lập trình hoặc Displays settings; notification không có `userInfo` và được post trên main actor. Nguồn: [didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification), [applicationDidChangeScreenParameters](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidchangescreenparameters%28_%3A%29).

**INFERENCE.** Khi nhận notification, `ScreenGeometryService` phải rebuild snapshot từ `NSScreen.screens`, hủy/di chuyển overlay đang orphan, re-resolve display cho window target và clamp restore frame. Vì notification không nêu display nào đổi, không được cập nhật cục bộ dựa vào `userInfo`.

**Quyết định:** public API, production-safe. Geometry snapshot được version hóa theo display change; `visibleFrame` không được giữ như config lâu dài.

---

## 4. Launch at Login

**FACT.** Từ macOS 13, `SMAppService` là public API để register và quản lý Login Items, LaunchAgents và LaunchDaemons. `SMAppService.mainApp` đại diện main application dưới dạng login item. `register()` khiến main app launch ở các lần login tiếp theo, phụ thuộc user approval; `unregister()` ngăn những lần launch sau nhưng không đóng main app đang chạy. `status` phản ánh trạng thái đăng ký/ủy quyền. Nguồn: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp), [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29), [unregister](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28%29).

**Quyết định:** dùng `SMAppService.mainApp.register()/unregister()` và render UI từ `status`; không cài plist thủ công vào `~/Library/LaunchAgents`, không cần helper chỉ để mở menu bar app.

**UNKNOWN.** UX phải kiểm thử trạng thái `requiresApproval` và trường hợp user đổi toggle từ System Settings khi app đang chạy.

---

## 5. App Sandbox và direct distribution

### 5.1 Sandbox không phù hợp core product

**FACT.** Apple yêu cầu App Sandbox cho app phát hành trên Mac App Store. Hướng dẫn chính thức liệt kê “use of accessibility APIs in assistive apps” trong các hoạt động không tương thích với App Sandbox; tài liệu Accessibility cũ của Apple nói rõ app điều khiển app khác không thể sandbox. Nguồn: [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [Accessibility Programming Guidelines for Cocoa](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Accessibility/cocoaAXIntro/cocoaAXintro.html).

**FACT.** Apple DTS ghi rõ không có entitlement `com.apple.security.accessibility` để mở quyền AX; quyền này do người dùng điều khiển trong Privacy & Security, và sandboxed app không thể dùng AX theo cách điều khiển app khác. Nguồn: [Apple Developer Forums — Entitlements, common hallucinations](https://developer.apple.com/forums/topics/code-signing-topic/code-signing-topic-entitlements).

**Quyết định:** target production v1 đặt `com.apple.security.app-sandbox = false`/không khai báo entitlement sandbox. Không tạo entitlement Accessibility không tồn tại. Mac App Store là track nghiên cứu tách biệt, không phải release blocker.

### 5.2 Developer ID, Hardened Runtime và notarization

**FACT.** Apple hỗ trợ phát hành ngoài Mac App Store bằng Developer ID. Notarization scan malicious content và vấn đề code-signing, sinh ticket để Gatekeeper xác minh; notarization yêu cầu Developer ID signature, secure timestamp và Hardened Runtime. Nguồn: [Developer ID](https://developer.apple.com/support/developer-id/), [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime).

**Quyết định:** beta/release pipeline dùng Developer ID Application certificate, Hardened Runtime, notarize và staple ticket. Chỉ thêm hardened-runtime exception khi có bằng chứng API cần nó; AX và Input Monitoring là user privacy permissions, không phải lý do để tắt Hardened Runtime.

**INFERENCE.** Giữ ổn định bundle identifier, signing identity và đường dẫn cài đặt giúp onboarding permission/update dễ dự đoán hơn; permission persistence qua update vẫn phải test trong R7-02, không được coi là contract chỉ từ code-signing docs.

---

## 6. Spaces/Desktop: ranh giới public API

### 6.1 Những gì public API làm được

**FACT.** `NSWorkspace.activeSpaceDidChangeNotification` chỉ báo một Spaces change đã xảy ra; notification object là shared workspace và không có `userInfo`. Nó không cung cấp Space ID hoặc thao tác move. Nguồn: [NSWorkspaceActiveSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification).

**FACT.** `NSWindow.CollectionBehavior.canJoinAllSpaces` và `.moveToActiveSpace` điều khiển behavior của một `NSWindow`. Apple định nghĩa `NSWindow` là cửa sổ mà **một app hiển thị**, và collection behavior thuộc chính object đó. Các API này phù hợp cho overlay/HUD của My Mac X, không phải handle tới cửa sổ của process khác. Nguồn: [NSWindow](https://developer.apple.com/documentation/appkit/nswindow), [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces), [isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace).

**FACT.** Public AX API được Apple công bố cho window manipulation cung cấp accessibility attributes/actions như focused window, position và size; tài liệu public không công bố một AX Space identifier hoặc action “move to Space N”. Nguồn: [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [kAXFocusedWindowAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute), [kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute), [kAXSizeAttribute](https://developer.apple.com/documentation/applicationservices/kaxsizeattribute).

### 6.2 Kết luận và policy

**INFERENCE có độ tin cậy cao.** Không có public API được Apple document để My Mac X đưa tùy ý cửa sổ của app khác sang Space/Desktop N. Có thể quan sát việc active Space đổi và có thể quản lý collection behavior của cửa sổ do My Mac X sở hữu, nhưng hai việc đó không đáp ứng yêu cầu sản phẩm.

**UNKNOWN.** Có thể mô phỏng UI/keyboard của Mission Control hoặc gọi symbols của SkyLight/CGS không được document, nhưng không có stability, compatibility hoặc review contract từ Apple. Các hướng đó không được xem là production API.

**Quyết định:**

- v1 hỗ trợ move giữa **physical displays** bằng AX frame trong global coordinates.
- v1 không hứa move cửa sổ app khác tới arbitrary Space.
- Có thể lắng nghe active-Space notification để đóng HUD/overlay hoặc reset prefix state.
- Cấm import, dynamic lookup hoặc fallback tới SkyLight/CGS/private symbols trong production target.
- Mọi nghiên cứu Spaces sau v1 nằm sau feature flag trong target thử nghiệm riêng và không được merge vào release path nếu chưa có public contract.

---

## 7. Bảng phân loại API và implementation boundary

| API/cơ chế | Public/private | Dùng trong v1 | Boundary đề xuất |
|---|---|---:|---|
| `AXIsProcessTrustedWithOptions` | Public | Có | `AccessibilityPermissionClient` |
| `AXUIElementCreateSystemWide`, copy/set attributes | Public | Có | `AccessibilityWindowClient` |
| `kAXFocusedApplication`, `kAXFocusedWindow`, `kAXPosition`, `kAXSize` | Public | Có | Adapter constants, không lộ ra UI |
| `CGEventTapCreate`, `CGEventTapEnable` | Public | Có, giới hạn Super Mode | `EventTapClient` |
| `CGPreflight/RequestListenEventAccess` | Public | Có nếu listen-only tap cần | `InputMonitoringPermissionClient` |
| `NSScreen.frame/visibleFrame/safeAreaInsets/auxiliary…` | Public | Có | `ScreenGeometryService` |
| `NSApplication.didChangeScreenParametersNotification` | Public | Có | `ScreenChangeObserver` |
| `SMAppService.mainApp` | Public | Có | `LaunchAtLoginClient` |
| `NSWorkspace.activeSpaceDidChangeNotification` | Public | Có, quan sát lifecycle | `WorkspaceObserver` |
| `NSWindow.CollectionBehavior` | Public | Có cho overlay/HUD của My Mac X | `OverlayWindowController` |
| SkyLight/CGS Space functions hoặc undocumented window tags | Private/undocumented | Không | Bị cấm trong production |

Boundary chung phải khiến domain/layout tests không import ApplicationServices, CoreGraphics event tap, AppKit hoặc ServiceManagement. Adapter chuyển mọi `AXError`, permission state và system notification thành typed domain result/event.

---

## 8. Acceptance checklist cho ba spike Sprint 0

### P0-03 — focused window + AX resize

- [ ] Fresh state: app phát hiện chưa có quyền, request không bị hiểu nhầm là synchronous grant.
- [ ] Grant/revoke trong runtime được phản ánh mà không restart bắt buộc.
- [ ] Tìm đúng focused window khi hai cửa sổ cùng process.
- [ ] Đọc position/size, kiểm tra settable, ghi và read-back trên Finder, Safari, Terminal, Xcode, Chrome, Electron.
- [ ] Báo typed unsupported/error cho sheet, dialog, minimized, non-resizable và native full-screen.
- [ ] 100 lần move/resize liên tiếp không hang app; retry hữu hạn.

### P0-04 — hotkey/Event Tap

- [ ] Tách test Accessibility và Input Monitoring trên user/VM sạch.
- [ ] `.listenOnly` quan sát đúng event mask; active filter chỉ swallow trong armed state.
- [ ] Deny/revoke không làm crash và không khiến tap spin/recreate liên tục.
- [ ] `tapDisabledByTimeout` và `tapDisabledByUserInput` reset state rồi re-enable đúng một lần.
- [ ] Callback không gọi AX/I/O/config/log nặng; không ghi ký tự hay title cửa sổ.
- [ ] Sleep/wake và relaunch không tạo duplicate tap/run-loop source.

### P0-05 — Notch/safe-area/multi-screen

- [ ] MacBook có Notch và Mac/external display không Notch.
- [ ] External display ở trái, phải, trên, dưới; có origin âm và mixed scaling.
- [ ] Dock trái/phải/dưới, auto-hide; menu bar auto-hide.
- [ ] Mirror mode, separate Spaces on/off và Stage Manager on/off.
- [ ] Cắm/rút/reorder display trong khi overlay mở không để orphan panel.
- [ ] Overlay không thành key/main window; preview và final frame lệch không quá 1 point.

---

## 9. Các unknown cần đóng trước khi qua Gate G0

1. TCC matrix thực tế cho active session Event Tap trên các macOS được support.
2. Ordering position/size và clamp behavior của sáu app đại diện.
3. Derived Notch gap trên desktop thường, menu bar auto-hide và native full-screen.
4. Hành vi `SMAppService.status` khi user đổi Login Items từ System Settings lúc app đang chạy.
5. Permission persistence khi cài bản update có cùng bundle ID/signing identity.
6. Overlay/HUD behavior khi active Space đổi hoặc Stage Manager chuyển set.

Nếu một unknown chỉ ảnh hưởng polish, ghi constraint và chuyển sang Sprint tương ứng. Nếu nó làm sai core move/resize, làm mất input hoặc yêu cầu private API, Gate G0 phải dừng cho tới khi có quyết định sản phẩm mới.
