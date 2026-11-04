# funny · Dynamic Notch

Native macOS music companion built with SwiftUI + AppKit. **Preview 0.2** attaches to the top edge of the screen and leaves the physical camera housing empty, with artwork on its left and a playback button on its right. Hover to expand into a player; leave to collapse. No third-party Swift dependencies.

## Cập nhật từ Music Island 0.1

Thoát bản cũ từ menu bar, hoặc `killall MusicIsland`. Trong thư mục `funny` đã clone:

```bash
git pull --ff-only
bash scripts/build-app.sh
open "dist/Dynamic Notch.app"
```

Tên app mới là **Dynamic Notch.app**. Nếu đã copy Music Island vào Applications, thay app cũ bằng bản mới trong `dist`. Không mở cả hai cùng lúc. Bundle identifier và tên executable được giữ nguyên để giảm xáo trộn quyền Automation.

Cài mới:

```bash
git clone https://github.com/NgDuonq/funny.git
cd funny
bash scripts/build-app.sh
open "dist/Dynamic Notch.app"
```

Cần **macOS 13+ và Swift 5.9+** (Xcode 15 / Command Line Tools tương ứng). Build mặc định ARM64 trên Apple Silicon. Chạy `xcode-select --install` nếu chưa có công cụ build.

## Giao diện mới

- Bám sát mép trên, nền đen liền với notch; giữ trống vùng camera thật.
- Thu gọn: ảnh bìa + nút play/pause ở hai bên notch. Hover mở rộng, rời chuột 0,35 giây thì thu lại.
- Mở rộng: tên bài, nghệ sĩ, nguồn, tiến trình, điều khiển và chọn trình phát.
- **Nút × ngay trên bảng mở rộng để thoát**. Chuột phải lên notch cũng có Thoát/Ẩn/Thử lại.
- Menu bar có bảng nguồn, quyền kết nối, lời LRC và giảm chuyển động.
- Tự ưu tiên màn hình có notch; màn không có notch dùng phần khuyết giả nhỏ ở giữa mép trên. Bản này chưa hỗ trợ chọn màn bằng tay.

## Các nguồn nhạc

| Nguồn | Cách kết nối | Phạm vi |
| --- | --- | --- |
| Spotify desktop | AppleScript / Automation | Metadata, ảnh bìa, play/pause, trước/sau, tua |
| Apple Music desktop | AppleScript / Automation | Metadata, play/pause, trước/sau, tua khi có thời lượng; chưa lấy ảnh bìa |
| SoundCloud web | Cầu nối trình duyệt | Metadata, play/pause, trước/sau qua nút trang; tua chỉ khi trang lộ HTML media |
| YouTube / YouTube Music | Cầu nối trình duyệt | Metadata từ Media Session hoặc DOM, HTML media và các nút khả dụng |
| Spotify Web / Apple Music Web | Cầu nối trình duyệt | Best effort: tùy Media Session, HTML media và nút trang; không cam kết đầy đủ với DRM |

Trình duyệt có adapter: **Google Chrome, Safari, Brave, Microsoft Edge**. Firefox chưa hỗ trợ. Web adapters đang thử nghiệm; DOM của trang có thể thay đổi. Không dùng private MediaRemote API và không tuyên bố bắt được mọi app của macOS.

### Native

Mở Spotify hoặc Music, phát nhạc rồi mở Dynamic Notch. App tự dò hai ứng dụng đang chạy và xin quyền Automation. Không tự khởi động trình phát. Bật/tắt từng nguồn trong menu bar. Nếu đã từ chối quyền, mở System Settings → Privacy & Security → Automation để cho phép, rồi bấm **Tự động / Thử lại**.

### Web (bật một lần cho trình duyệt muốn dùng)

1. Bấm icon waveform trên menu bar → bật tên trình duyệt.
2. Cho phép quyền Automation khi macOS hỏi.
3. **Chrome:** View → Developer → Allow JavaScript from Apple Events. Brave/Edge có tùy chọn tương tự tùy phiên bản.
4. **Safari:** Settings → Advanced → Show features for web developers; trong Developer settings/Develop bật Allow JavaScript from Apple Events (vị trí tùy phiên bản).
5. Phát nhạc trên website hỗ trợ, bấm **Tự động / Thử lại** nếu vừa cấp quyền.

Chỉ nên bật các trình duyệt cần dùng. App kiểm tra URL và chỉ chạy script đọc media trên các host cho phép: SoundCloud, YouTube, YouTube Music, Spotify Web, Apple Music Web. Không đọc nội dung tab khác, không lưu lịch sử. Tối đa 12 tab nhạc mỗi trình duyệt trong một lượt dò.

[Tài liệu Chromium về Apple Events](https://www.chromium.org/developers/applescript/) · [Tài liệu Safari Developer settings](https://developer.apple.com/documentation/safari-developer-tools/developer-settings)

### Nhiều nguồn cùng mở

Tự động ưu tiên nguồn đang phát. Nếu nguồn hiện tại vẫn phát thì giữ nguyên để tránh nhảy qua lại. Có thể ghim một nguồn trong **Trình phát**. Nguồn ghim đóng thì app chờ, không gửi lệnh sang app khác. Lệnh web kiểm tra lại cửa sổ, vị trí tab, URL và tên bài trước khi điều khiển; nếu tab di chuyển/đổi bài, chờ lượt dò kế tiếp rồi thử lại.

Nút không được nguồn hỗ trợ sẽ bị vô hiệu hóa. Trang chỉ cung cấp metadata mà không có thời lượng sẽ hiện “Không hỗ trợ tua”. Không đoán thời lượng hoặc dùng tiến trình giả cho nguồn thật.

## Lời và demo

Nhập `.lrc` UTF-8 dưới 1 MB từ menu bar. Hỗ trợ tiếng Việt, timestamp phân số, nhiều timestamp trên dòng và `[offset:+250]`/`[offset:-250]`. Lời chỉ gắn với bài hiện tại, chưa có tải LRCLIB hay lưu cache. Demo là giao diện im lặng; dùng **Tự động / Thử lại** để quay về nhạc thật.

## Tối ưu và giới hạn

- Dò nguồn trên hàng đợi nền mỗi 3 giây, không dò khi sleep màn hình/máy.
- Chỉ kiểm tra app đang chạy và nguồn đã bật; lỗi một nguồn không làm ngắt nguồn khác.
- Nguồn bị lỗi được tạm bỏ qua cho tới khi người dùng Thử lại, tránh hỏi quyền liên tục.
- Nội suy thời gian bằng monotonic clock. Chỉ tải ảnh HTTPS khi đổi bài.
- Reduce Motion/chế độ Giảm chuyển động tắt animation mở rộng. Chưa có số CPU/RAM/pin đo trên Mac thật.
- Chưa có FFT/spectrum theo âm thanh, mascot, hỗ trợ Firefox hay hỗ trợ mọi ứng dụng toàn hệ thống.
- Bản build ký ad-hoc, chưa notarize. Không cần tắt SIP/Gatekeeper. Apple Events từ app đóng gói vẫn cần thử quyền trên Mac thực tế.

## Kiểm tra

```bash
swift test
node --test Tests/WebBridgeTests/*.test.cjs
bash scripts/build-app.sh
"dist/Dynamic Notch.app/Contents/MacOS/MusicIsland" --smoke-test
```

CI macOS kiểm tra LRC, đồng hồ, chọn nguồn, web adapters với DOM fixtures, build `.app` và mở app kiểm tra panel/resource đóng gói. ZIP ở Actions artifacts. **Tests bằng fixtures không chứng minh hoạt động với website live**; cần thử SoundCloud/YouTube, quyền Automation và từng browser trên máy thật.

Checklist thực tế: hover/thu gọn không che camera; × thoát; native pause/tua/đổi bài; web play/pause; đổi/đóng tab; nhiều nguồn; từ chối quyền; sleep/wake; cắm/rút màn; fullscreen; Reduce Motion.

## Cấu trúc

- `Sources/MusicIsland`: SwiftUI, AppKit panel, model, `MediaBridge.swift` và `Resources/WebPlayer.js`.
- `Sources/IslandCore`: parser LRC, đồng hồ, quy tắc chọn nguồn.
- `Tests`: XCTest và Node tests cho web adapters.
- `scripts/build-app.sh`: đóng gói app + SwiftPM resources, ký ad-hoc.

Cảm hứng từ [lvt1693/music-bar](https://github.com/lvt1693/music-bar). Đây là triển khai Swift độc lập, không sao chép code hay assets của bản Windows.
