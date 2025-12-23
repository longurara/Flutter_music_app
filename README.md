# Music (Flutter)

Desktop-first Flutter music player with vinyl/CD themes, rich audio controls, lyrics, and optional Google Drive streaming (beta).
## English
### Overview
- Desktop-first Flutter music player with vinyl turntable / CD deck / artwork-only themes.
- Queue, shuffle/repeat, history, lossless/Hi-Res indicator from `media_kit` audio params.
- Lyrics via lrclib (prefers synced) with fallback to lyrics.ovh; cached per track.
- Audio controls: preamp, 5-band EQ, Auto-EQ from loopback/mic (beta, input gain), room calibration via mic with suggested gains, playback speed, sleep timer, volume sheet.
- Windows: SMTC (media keys + metadata), optional WASAPI Exclusive (disables EQ/preamp for bit-perfect), window management.
- Sources: recursive offline folder scan for mp3/flac/m4a/aac/wav/ogg/opus, custom stream URLs. Google Drive streaming (public links or OAuth) is experimental and UI is hidden by default.

### Online features (beta/hidden)
- Stream public/shared Google Drive files or folders without sign-in.
- OAuth sign-in to list/stream personal Drive audio.
- UI is hidden (`_showOnlineFeatures = false` in `lib/main.dart`); enable only after you add your own Desktop OAuth client and accept the risks.

### Requirements
- Flutter SDK 3.10+ (stable) and desktop toolchains you target.
- Windows for SMTC and WASAPI Exclusive; macOS/Linux can play audio but miss Windows-only features.
- Microphone permission for Auto-EQ and room calibration; loopback/“Stereo Mix” input improves accuracy.
- Google Drive OAuth Desktop client ID if you want Drive features.

### Setup & run
```bash
flutter pub get
# run Windows desktop
flutter run -d windows
# or choose another desktop target if enabled (macos/linux)
```

### Google Drive setup (optional, beta)
1. Create OAuth Client type **Desktop** in Google Cloud Console (Credentials → Create OAuth client → Desktop app).
2. Update `clientId` in `GoogleDriveService` initialization in `lib/main.dart`.
3. Set `_showOnlineFeatures` to `true` in `lib/main.dart` if you want the Drive/Stream UI.
4. On sign-in, the app opens the consent page; copy/paste the verification code to grant `drive.readonly`.
5. Public links work without sign-in; personal library streaming needs OAuth and stable network.

### Quick usage
- Click **Add music** → **Add offline folder** to scan recursively (supports listed formats); pick via FilePicker or paste a path.
- Open **Library** to browse Albums/Songs; open an album to play/shuffle tracks.
- **Settings**: tweak EQ/preamp, toggle Auto-EQ (disable WASAPI exclusive first), run room calibration, pick audio device, set speed, sleep timer, theme, lyrics source, view history.
- **Devices**: refresh and choose output; toggle WASAPI Exclusive (Windows).
- **Lyrics overlay**: tap the chat icon to show lyrics beside Now Playing.

### Structure
- `lib/main.dart`: UI, sheets (Library/Queue/Settings/Drive/Devices), theme, dynamic background.
- `lib/state/player_notifier.dart`: Playback state, queue, SMTC, EQ/Auto-EQ, WASAPI, Drive, lyrics, history.
- `lib/services/google_drive_service.dart`: Parse link/id, public streaming, OAuth helpers, Drive listing.
- `lib/services/lyrics_service.dart`: lrclib & lyrics.ovh clients.
- `lib/services/room_calibration_service.dart`: Mic capture and band gain suggestions.
- `lib/models/track.dart`: Track model & metadata.

### Development & testing
- Lint: `flutter_lints` (see `analysis_options.yaml`).
- Tests: `flutter test`.
- Upgrades: prefer `flutter pub upgrade --major-versions` then verify desktop builds.

### Known limitations
- Drive/online streaming is experimental; sign-in or streaming may be flaky.
- EQ/Auto-EQ disabled when WASAPI Exclusive is on (to keep bit-perfect path).
- UI optimized for desktop; not tuned for small mobile screens.

---

## Tiếng Việt
### Tổng quan
- Trình phát nhạc ưu tiên desktop với 3 chủ đề: vinyl turntable, CD deck, hoặc chỉ artwork.
- Hàng chờ, shuffle/repeat, lịch sử nghe, nhãn Lossless/Hi-Res từ thông số `media_kit`.
- Lời bài hát từ lrclib (ưu tiên lyric đồng bộ) và fallback lyrics.ovh; cache theo bài.
- Âm thanh: preamp, EQ 5 băng, Auto-EQ realtime từ loopback/mic (beta, chỉnh gain đầu vào), đo phòng bằng mic và gợi ý gain, tốc độ phát, hẹn giờ ngủ, bảng volume.
- Windows: SMTC (media keys + metadata), tùy chọn WASAPI Exclusive (tắt EQ/preamp để giữ bit-perfect), quản lý cửa sổ.
- Nguồn phát: quét thư mục offline đệ quy (mp3/flac/m4a/aac/wav/ogg/opus), stream URL tùy ý. Google Drive (public/OAuth) ở trạng thái thử nghiệm và ẩn UI mặc định.

### Tính năng online (beta/ẩn)
- Stream file/thư mục công khai từ Google Drive không cần đăng nhập.
- Đăng nhập OAuth để quét/stream thư viện Drive cá nhân.
- UI đang tắt (`_showOnlineFeatures = false` trong `lib/main.dart`); chỉ bật khi bạn tự cấu hình OAuth client Desktop và chấp nhận rủi ro.

### Yêu cầu
- Flutter SDK 3.10+ (stable) và toolchain desktop bạn dùng.
- Windows để có SMTC và WASAPI Exclusive; macOS/Linux vẫn phát nhạc nhưng thiếu tính năng Windows-only.
- Quyền microphone cho Auto-EQ và đo phòng; input loopback/“Stereo Mix” sẽ chính xác hơn.
- OAuth client Google Drive (Desktop) nếu muốn dùng Drive.

### Cài đặt & chạy
```bash
flutter pub get
# chạy desktop Windows
flutter run -d windows
# hoặc chọn thiết bị desktop khác nếu đã bật (macos/linux)
```

### Cấu hình Google Drive (tùy chọn, beta)
1. Tạo OAuth Client **Desktop** trong Google Cloud Console (Credentials → Create OAuth client → Desktop app).
2. Cập nhật `clientId` trong khởi tạo `GoogleDriveService` ở `lib/main.dart`.
3. Đổi `_showOnlineFeatures` thành `true` trong `lib/main.dart` nếu muốn hiện UI Drive/Stream.
4. Khi đăng nhập, ứng dụng mở trang consent; copy/paste mã xác minh để cấp quyền `drive.readonly`.
5. Link công khai dùng được không cần đăng nhập; thư viện cá nhân cần OAuth và mạng ổn định.

### Sử dụng nhanh
- Nút **Add music** → **Add offline folder** để quét đệ quy (lọc các định dạng hỗ trợ); nhập đường dẫn hoặc chọn bằng FilePicker.
- Mở **Library** để duyệt Album/Bài hát; mở album để Play/Shuffle.
- **Settings**: chỉnh EQ/preamp, bật Auto-EQ (tắt WASAPI exclusive trước), đo Room EQ, chọn thiết bị audio, tốc độ phát, timer ngủ, theme, nguồn lyric, xem lịch sử.
- **Devices**: làm mới và chọn đầu ra; bật WASAPI Exclusive (Windows).
- **Lyrics overlay**: nhấn icon chat để xem lyric song song Now Playing.

### Cấu trúc thư mục
- `lib/main.dart`: UI, các sheet Library/Queue/Settings/Drive/Devices, theme, nền động.
- `lib/state/player_notifier.dart`: Logic phát, hàng chờ, SMTC, EQ/Auto-EQ, WASAPI, Drive, lyrics, lịch sử.
- `lib/services/google_drive_service.dart`: Parse link/id, stream công khai, OAuth helper, duyệt Drive.
- `lib/services/lyrics_service.dart`: Gọi lrclib & lyrics.ovh.
- `lib/services/room_calibration_service.dart`: Thu mic, tính gain đề xuất cho từng băng.
- `lib/models/track.dart`: Model Track & metadata.

### Phát triển & kiểm thử
- Lint: `flutter_lints` (xem `analysis_options.yaml`).
- Kiểm thử: `flutter test`.
- Nâng cấp dependency: ưu tiên `flutter pub upgrade --major-versions` rồi build desktop kiểm tra.

### Hạn chế đã biết
- Tính năng Drive/stream online còn thử nghiệm; đăng nhập hoặc stream có thể không ổn định.
- EQ/Auto-EQ bị tắt khi bật WASAPI Exclusive (để giữ signal bit-perfect).
- UI tối ưu cho desktop; chưa tối ưu cho màn hình mobile nhỏ.
