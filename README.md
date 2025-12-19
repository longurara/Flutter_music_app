# Music (Flutter)

Ứng dụng nghe nhạc Flutter (tập trung trải nghiệm desktop, đặc biệt Windows) với giao diện đĩa than/CD, hỗ trợ phát nhạc cục bộ, Google Drive (Chưa fix), lời bài hát và điều khiển hệ thống.

## Tính năng chính
- Phát nhạc cục bộ từ nhiều định dạng: mp3, flac, m4a, aac, wav, ogg, opus.
- Stream file hoặc thư mục công khai từ Google Drive; đăng nhập OAuth để duyệt toàn bộ Drive của bạn. (lỗi chưa fix)
- Giao diện trình phát có ba chủ đề: đĩa vinyl, CD deck, hoặc chỉ hiển thị bìa album.
- Lời bài hát tự động (lrclib, lyrics.ovh), hỗ trợ lyric đồng bộ nếu có.
- Điều khiển phát: hàng đợi, shuffle, repeat, tua, vòng lặp A-B, tốc độ phát, volume, preamp và EQ 5 băng tần.
- Tích hợp SMTC Windows (media keys, hiển thị bài hát) và quản lý cửa sổ không viền qua `window_manager`.
- Gợi ý màu nền từ bìa album (palette) và cache artwork để tải nhanh.

## Công nghệ
- Flutter 3.10+ (Dart 3.10+), Material 3.
- `media_kit` cho phát nhạc đa nền tảng, `provider` cho state, `window_manager` và `smtc_windows` cho trải nghiệm desktop.
- `google_sign_in`, `googleapis`, `googleapis_auth` cho tích hợp Drive; `palette_generator`, `cached_network_image` cho hiển thị bìa.

## Yêu cầu
- Flutter SDK (channel stable) và toolchain cho nền tảng bạn chạy.
- Windows để dùng SMTC, phím media và WASAPI exclusive; nền tảng khác vẫn chạy nhưng các tính năng này có thể giới hạn.
- OAuth client Google Drive (Desktop) nếu muốn đăng nhập Drive cá nhân.

## Cài đặt & chạy
```bash
flutter pub get
# Chạy desktop Windows
flutter run -d windows
```

## Cấu hình Google Drive OAuth (chưa fix)
Ứng dụng đã khai báo `clientId` trong `GoogleDriveService`, nhưng bạn nên dùng OAuth client riêng:

1. Vào Google Cloud Console → Credentials → Create OAuth client → Desktop app.
2. Lấy `Client ID` và cập nhật trong [lib/main.dart](lib/main.dart#L33-L40) hoặc truyền qua biến môi trường/cấu hình theo cách bạn chọn.
3. Khi đăng nhập, ứng dụng hiển thị mã thiết bị; mở đường dẫn xác minh, nhập mã và cấp quyền Drive.

Ứng dụng vẫn có thể stream file/folder công khai chỉ với liên kết chia sẻ (không cần đăng nhập).

## Cấu trúc thư mục rút gọn
- [lib/main.dart](lib/main.dart): Khởi tạo app, chủ đề Material 3, màn hình Player.
- [lib/state/player_notifier.dart](lib/state/player_notifier.dart): Core logic phát nhạc, hàng đợi, SMTC, EQ, Drive, lyrics.
- [lib/services/google_drive_service.dart](lib/services/google_drive_service.dart): Trích xuất link/ID, stream công khai, OAuth device flow, duyệt file Drive.
- [lib/services/lyrics_service.dart](lib/services/lyrics_service.dart): Lấy lời bài hát (lrclib/lyrics.ovh).
- [lib/models/track.dart](lib/models/track.dart): Mô hình bài hát.

## Ghi chú sử dụng
- Có thể chọn thiết bị audio và bật/tắt WASAPI exclusive trên Windows.
- Lyric được cache theo bài; lyric đồng bộ dùng để highlight khi phát.
- Palette bìa album được cache để tránh tính lại khi chuyển bài.
- Nếu gặp lỗi phát từ Drive, thử làm mới token hoặc kiểm tra lại quyền truy cập file. (chưa fix)

## Đóng góp & phát triển
- Tuân thủ lint mặc định của `flutter_lints`.
- Chạy kiểm thử mặc định: `flutter test`.
- Khi cập nhật dependencies, ưu tiên `flutter pub upgrade --major-versions` và kiểm tra lại build desktop.


## Lỗi hiện có:
- Không đăng nhập được google drive hoặc stream file online