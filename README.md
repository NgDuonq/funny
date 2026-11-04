# funny · Music Island for macOS

A small native music companion for your Mac. SwiftUI + AppKit, no third-party package dependencies.

**Preview 0.1:** menu bar player, a floating island below the notch/menu bar, Spotify desktop controls and local synchronized lyrics. The first launch uses a silent demo so you can try the interface without granting permissions.

## Chạy trên Mac

Yêu cầu **macOS 13+**, Xcode Command Line Tools có **Swift 5.9+** (Xcode 15 trở lên). Tối ưu build mặc định cho kiến trúc máy: ARM64 trên M1/M2/M3/M4.

```bash
git clone https://github.com/NgDuonq/funny.git
cd funny
bash scripts/build-app.sh
open "dist/Music Island.app"
```

Nếu chưa có công cụ build: chạy `xcode-select --install`. Nếu Swift cũ hơn 5.9, cập nhật Xcode/Command Line Tools trước.

App xuất hiện ở biểu tượng **waveform trên menu bar**, không có icon trong Dock. Bấm biểu tượng để mở bảng điều khiển; rê chuột lên Island để mở thanh tua và lời. Có thể ẩn Island hoặc thoát trong menu bar.

### Spotify

1. Mở **Spotify desktop**, phát một bài.
2. Bấm **Kết nối Spotify** trong Music Island.
3. Cho phép điều khiển Spotify khi macOS hỏi quyền Automation.
4. Dùng play/pause, bài trước/sau hoặc kéo thanh tiến trình.

Nếu bị từ chối quyền: System Settings → Privacy & Security → Automation → cho phép Spotify dưới Music Island (hoặc tiến trình macOS ghi nhận), rồi bấm kết nối lại. Bản build dùng chữ ký ad-hoc; bản tải từ Actions chưa được Apple notarize. Nên tự build bản đầu trên máy. Không cần tắt SIP hay Gatekeeper.

### Lời bài hát

Bấm nút nhập lời trong menu bar, chọn file `.lrc` UTF-8 dưới 1 MB. Ví dụ:

```lrc
[00:00.00]Một chút nhạc, một khoảng trời riêng.
[00:08.50]Đèn thành phố trôi qua thật chậm.
```

Hỗ trợ nhiều timestamp trên một dòng và `[offset:+250]`/`[offset:-250]` (mili giây). Lời gắn với bài đang phát, tự xóa khi đổi bài; chưa lưu lại giữa các lần mở app. Nội dung demo do dự án tự viết, không phải lời nhạc thương mại.

## Có gì / chưa có gì

| Có trong 0.1 | Để sau |
| --- | --- |
| Menu bar + Island nổi dưới notch, mở rộng khi hover | Bao quanh notch, chọn màn hình riêng |
| Spotify: tên bài, nghệ sĩ, ảnh bìa, tua, play/pause, chuyển bài | Apple Music, YouTube/trình duyệt |
| Demo không cần Spotify, không phát âm thanh | Spectrum theo âm thanh thật / Core Audio taps |
| Lời LRC đồng bộ theo dòng | LRCLIB, cache lời, karaoke theo từng từ |
| Giảm chuyển động và hỗ trợ Reduce Motion | Mascot, Music Strip, màu tự lấy từ ảnh bìa |

Island dùng màn hình đầu tiên của hệ thống, đặt dưới vùng menu/notch để không che camera. Hiện chưa có kéo thả/ghi nhớ vị trí. Nút tiết kiệm chuyển động tắt animation mở rộng, không phải chế độ tối ưu pin đã benchmark.

## Cấu trúc

- `Sources/MusicIsland`: app lifecycle, panel, SwiftUI, Spotify bridge, player state.
- `Sources/IslandCore`: LRC parser và đồng hồ phát độc lập UI.
- `Tests/IslandCoreTests`: kiểm tra Unicode, timestamp, offset và nội suy vị trí phát.
- `Resources`: Info.plist, mô tả quyền Automation và entitlement.
- `scripts/build-app.sh`: build release, đóng gói `.app`, ký ad-hoc.
- `.github/workflows/macos.yml`: test và build trên macOS, xuất ZIP trong Actions artifacts.

Spotify được đọc mỗi 2 giây bằng AppleScript trên hàng đợi nền. Tiến trình được nội suy bằng monotonic clock, không gọi Spotify theo frame. Ảnh tải khi đổi bài. Polling dừng khi sleep màn hình/máy và sau lỗi quyền; app không thu âm hay gửi dữ liệu nhạc đến server của dự án. Ảnh bìa được tải từ URL Spotify cung cấp.

## Kiểm tra

```bash
swift test
bash scripts/build-app.sh
```

Checklist trên máy thật:

- Demo: mở menu bar, hover Island, pause/resume, tua, ẩn/hiện và thoát.
- Spotify chưa mở / không có bài / từ chối quyền: có thông báo, không hỏi quyền liên tục.
- Spotify phát: tên bài, ảnh bìa, thời lượng, play/pause, tua và chuyển bài.
- Nhập LRC tiếng Việt; kiểm tra lời đổi đúng mốc; đổi bài phải xóa lời cũ.
- Sleep/wake, fullscreen, cắm/rút màn hình và Reduce Motion.
- Kiểm tra Activity Monitor khi idle/phát nhạc. Chưa có số CPU/RAM/pin được đo trên máy thật.

CI xác nhận compile/test, không thay thế kiểm tra giao diện và quyền Automation trên Mac thật.

## Nguồn cảm hứng

Lấy cảm hứng từ [lvt1693/music-bar](https://github.com/lvt1693/music-bar). Đây là bản triển khai Swift độc lập, chưa sao chép mã nguồn, phông chữ hay tài nguyên của dự án Windows.
