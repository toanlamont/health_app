# BÁO CÁO CÔNG NGHỆ — ỨNG DỤNG HEARTBEAT (health_app)

> Tài liệu liệt kê toàn bộ công nghệ, framework, thư viện và API của ứng dụng theo thứ tự: **Flutter (client) → giao tiếp API → FastAPI (server) → hạ tầng**.
>
> **Nguồn dữ liệu**
> - **Flutter / thư viện / API app gọi**: từ `health_app/pubspec.yaml`, `pubspec.lock`, `lib/` → đã kiểm chứng.
> - **Backend FastAPI / thuật toán nhịp tim / CSDL / triển khai**: từ source thật `health_api/` (`app/ppg.py`, `app/api/*.py`, `app/models.py`, `Dockerfile`, `fly.toml`...) → đã kiểm chứng.
> - Riêng các hàm POS, CHROM, periodogram, SNR nằm trong thư viện **rPPG-Toolbox** (thư mục `vendor_rppg/` không có trong repo), nên phần công thức của chúng được mô tả theo bản gốc công bố của thư viện.
> - `DESIGN.html` chỉ là tài liệu thiết kế ban đầu và **đã lệch nhiều so với code** (xem mục 8).

---

## 1. Tổng quan ứng dụng

| Mục | Nội dung |
|---|---|
| Tên ứng dụng | **HeartBeat** (package: `health_app`) |
| Loại | Ứng dụng theo dõi sức khỏe cá nhân (mobile, đa nền tảng) |
| Application ID | `com.heartbeat.health_app` |
| Phiên bản | `1.0.0+1` |
| Ngôn ngữ giao diện | Tiếng Việt (mặc định `vi`), hỗ trợ thêm `en` |
| Nền tảng | Android, iOS (Flutter cross-platform) |
| Tính năng cốt lõi | Đo nhịp tim bằng **camera trước** qua khuôn mặt (kỹ thuật **rPPG** – remote photoplethysmography) |
| Tính năng phụ | Dashboard, lịch sử nhịp tim, theo dõi cân nặng/BMI, theo dõi dinh dưỡng (calo), mục tiêu sức khỏe, nhắc nhở, hồ sơ sức khỏe, đăng nhập/đăng ký |

### 1.1. Kiến trúc tổng thể

```
┌────────────────────────────────────────────────────────────┐
│                  MOBILE APP  (Flutter / Dart)              │
│  UI (Material 3) · BLoC · Camera + ML Kit · fl_chart       │
│  Dio (HTTP) · flutter_secure_storage (lưu JWT)             │
└───────────────────────────┬────────────────────────────────┘
                            │  HTTPS · REST/JSON · Bearer JWT
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Cloudflare (domain toannd.work)  →  Fly.io (region sin)   │
│  TLS · force_https · máy tự tắt/bật                        │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────────┐
│     BACKEND  Python 3.14 / FastAPI / Uvicorn  — /api/v1    │
│  Auth JWT+bcrypt · CRUD sức khỏe · Dinh dưỡng · Dashboard  │
│  Engine rPPG: POS + CHROM + periodogram + bỏ phiếu         │
└───────────────────────────┬────────────────────────────────┘
                            ▼
              SQLite (SQLAlchemy async + aiosqlite)
              trên volume Fly.io  /app/data/health.db
```

---

## 2. CLIENT — Flutter / Dart

### 2.1. Nền tảng chính

| Công nghệ | Phiên bản | Vai trò |
|---|---|---|
| **Flutter SDK** | `>= 3.44.0` | Framework UI đa nền tảng, 1 codebase cho Android + iOS |
| **Dart SDK** | `^3.13.4` (`>=3.13.4 <4.0.0`) | Ngôn ngữ lập trình, null-safety, `sealed class`, async/await, `Stream` |
| **Material 3 / Material Design** | `uses-material-design: true` | Hệ thống thành phần UI (`NavigationBar`, `Scaffold`, `Card`...) |
| **flutter_localizations** | (SDK) | Địa phương hóa: Material/Widgets/Cupertino delegates cho `vi`, `en` |
| **cupertino_icons** | `^1.0.8` | Bộ icon phong cách iOS |

### 2.2. Danh sách thư viện (dependencies)

| # | Thư viện | Phiên bản khai báo | Phiên bản khóa (lock) | Mục đích sử dụng trong app |
|---|---|---|---|---|
| 1 | `camera` | ^0.12.1 | 0.12.1 (+ `camera_android_camerax` 1.0.9) | Mở camera trước, **stream từng frame ảnh** (định dạng NV21) để lấy tín hiệu rPPG; khóa focus/exposure khi đo |
| 2 | `google_mlkit_face_detection` | ^0.12.0 | 0.12.0 (+ `google_mlkit_commons` 0.9.0) | **Nhận diện khuôn mặt + landmark (mắt)** để xác định 3 vùng da (trán, 2 má) làm vùng đọc tín hiệu (ROI). Model chạy **on-device** (bundle trong APK) |
| 3 | `screen_brightness` | ^2.1.2 | 2.1.11 | Điều khiển độ sáng màn hình (khai báo trong pubspec; hiện chưa thấy được import trong `lib/`) |
| 4 | `dio` | ^5.7.0 | 5.11.1 | HTTP client gọi REST API; dùng `BaseOptions`, **interceptor** gắn `Authorization: Bearer`, timeout riêng cho request phân tích |
| 5 | `flutter_bloc` | ^9.1.0 | 9.1.1 | Quản lý trạng thái theo mô hình **BLoC** (`AuthBloc`, `BlocProvider`, `BlocBuilder`) |
| 6 | `go_router` | ^14.8.0 | 14.8.1 | Routing khai báo (khai báo trong pubspec; hiện app điều hướng bằng `NavigationBar` + `IndexedStack`, chưa thấy import `go_router` trong `lib/`) |
| 7 | `flutter_secure_storage` | ^9.2.4 | 9.2.4 | Lưu **access token (JWT)** an toàn: Keychain (iOS) / Keystore (Android) |
| 8 | `fl_chart` | ^0.70.2 | 0.70.2 | Vẽ biểu đồ đường (nhịp tim, cân nặng, calo...) trong `metric_chart.dart` |
| 9 | `intl` | ^0.20.2 | 0.20.3 | Định dạng ngày giờ (`DateFormat`), dữ liệu locale tiếng Việt (`initializeDateFormatting('vi')`) |
| 10 | `google_fonts` | ^6.2.1 | 6.3.3 | Font **Nunito Sans** cho toàn bộ `TextTheme` |

### 2.3. Thư viện phát triển (dev_dependencies)

| Thư viện | Phiên bản | Mục đích |
|---|---|---|
| `flutter_test` | (SDK) | Unit test & widget test |
| `flutter_lints` | ^6.0.0 (lock: 2.0.35) | Bộ quy tắc lint chuẩn Flutter (`analysis_options.yaml`) |

### 2.4. Công nghệ native / build

| Nền tảng | Công nghệ | Chi tiết |
|---|---|---|
| Android | **Gradle Kotlin DSL** (`build.gradle.kts`) | Plugin `com.android.application`, `dev.flutter.flutter-gradle-plugin` |
| Android | **Kotlin** + **Java 17** | `sourceCompatibility/targetCompatibility = VERSION_17`, `jvmTarget = JVM_17` |
| Android | **AndroidX Concurrent Futures** | `androidx.concurrent:concurrent-futures:1.2.0` (phụ trợ cho CameraX) |
| Android | **CameraX** | Plugin `camera_android_camerax` đứng sau `camera` |
| Android | Quyền (Manifest) | `CAMERA`, `INTERNET`; `usesCleartextTraffic="true"` (cho phép HTTP khi dev local) |
| iOS | **Swift** + Xcode project | `AppDelegate.swift`, `SceneDelegate.swift`, storyboard Launch/Main |
| iOS | **CocoaPods / Xcode build** | `Runner.xcodeproj`, `Info.plist` |

### 2.5. Cấu trúc thư mục source (`lib/`)

```
lib/
├── main.dart                     # Entry point: khởi tạo locale 'vi', MaterialApp, BlocProvider<AuthBloc>
├── app/
│   ├── constants.dart            # apiBaseUrl (production) & localApiBaseUrl (dev)
│   ├── home_shell.dart           # NavigationBar 5 tab + IndexedStack giữ state
│   └── theme.dart                # Light/Dark theme Material 3 + Google Fonts
├── core/
│   └── api_client.dart           # Singleton Dio + interceptor JWT + SecureStorage
├── features/
│   ├── auth/                     # auth_bloc.dart, login_screen.dart
│   ├── dashboard/                # dashboard_screen.dart  (tổng quan)
│   ├── heart_rate/               # measure_screen.dart, signal_recorder.dart  (rPPG)
│   ├── history/                  # history_screen.dart    (lịch sử nhịp tim)
│   ├── nutrition/                # meals_screen.dart      (bữa ăn / calo)
│   ├── weight/                   # weight_screen.dart     (cân nặng / BMI)
│   ├── goals/                    # goals_screen.dart      (mục tiêu)
│   ├── reminders/                # reminders_screen.dart  (nhắc nhở)
│   └── profile/                  # profile_screen.dart    (hồ sơ sức khỏe)
└── widgets/
    ├── metric_card.dart          # Thẻ chỉ số tái sử dụng
    └── metric_chart.dart         # Biểu đồ dùng fl_chart
```

Quy mô: ~**4.500 dòng Dart** trong `lib/` (lớn nhất: `measure_screen.dart` ~987 dòng).

### 2.6. Mẫu thiết kế & kỹ thuật lập trình đã dùng

| Kỹ thuật | Nơi dùng |
|---|---|
| **BLoC pattern** (Event → Bloc → State) với `sealed class` | `auth_bloc.dart` (events: `AuthLogin`, `AuthRegister`, `AuthCheckToken`, `AuthLogout`; states: `Initial/Loading/Authenticated/Unauthenticated/Error`) |
| **Singleton** | `ApiClient` (factory constructor trả về instance duy nhất) |
| **Interceptor (Dio)** | Tự đọc token từ SecureStorage và gắn header `Authorization: Bearer <token>` cho mọi request |
| **Auto-login** | `AuthCheckToken` → đọc token → gọi `GET /auth/me`; lỗi thì xóa token |
| **IndexedStack** | Giữ nguyên state/scroll các tab khi chuyển qua lại |
| **Future.wait** | Gọi nhiều API song song khi tải màn hình (dashboard, weight, meals...) |
| **StreamController (broadcast)** | `SignalRecorder.progressStream` báo tiến độ đo |
| **Timer.periodic** | Gọi “đo thử trực tiếp” (live poll) 2 giây/lần |
| **Theme sáng/tối** | `lightTheme` / `darkTheme` trong `theme.dart` |
| **Local hóa tiếng Việt** | `locale: vi`, `initializeDateFormatting('vi')`, định dạng “EEEE, d 'tháng' M” |
| **Unit test** | `test/roi_mapping_test.dart`, `test/roi_smoothing_test.dart`, `test/widget_test.dart` |

---

## 3. TÍNH NĂNG CỐT LÕI — ĐO NHỊP TIM BẰNG rPPG (CAMERA TRƯỚC)

> Lưu ý: `DESIGN.html` mô tả đo bằng **ngón tay + flash** và lọc trên máy. **Code thực tế**: đo bằng **khuôn mặt (camera trước)** và **gửi trung bình màu về backend để phân tích** (mục 3.2).

### 3.1. Quy trình trên thiết bị (Flutter)

| Bước | Mô tả | Công nghệ |
|---|---|---|
| 1 | Mở **camera trước**, độ phân giải `medium`, `ImageFormatGroup.nv21`, tắt audio | `camera` |
| 2 | Khóa focus (`FocusMode.locked`); sau giai đoạn warm-up khóa **exposure** (tránh auto-exposure tạo dao động giả giống mạch) | `camera` |
| 3 | Nhận diện khuôn mặt (`FaceDetectorMode.fast`, bật `enableLandmarks`), chạy mỗi ~5 frame | `google_mlkit_face_detection` |
| 4 | Tính **3 vùng da (ROI): trán + 2 má**, neo theo vị trí 2 mắt (không dùng bounding box để tránh dính tóc/kính) | `skinPatches()` |
| 5 | Làm mượt vị trí ROI giữa các frame (hệ số `roiFollowRate = 0.15`) và **ánh xạ tọa độ có xoay** (0/90/180/270°) về buffer ảnh | `steadyRois()`, `mapRotatedRectToBuffer()` |
| 6 | Với mỗi frame, tính **trung bình R, G, B** của từng vùng (và độ sáng/phương sai) | Dart thuần |
| 7 | `SignalRecorder` ghi lại `times[]` + `values[]` (R,G,B × số vùng): **30 giây**, bỏ **2 giây warm-up**, tự reset nếu mất frame > 2 giây | `signal_recorder.dart` |
| 8 | Mỗi 2 giây (sau giây thứ 8) gửi “**đo thử**” (`save: false`) để hiển thị BPM tạm thời | `Dio` + `Timer.periodic` |
| 9 | Hết 30 giây gửi toàn bộ tín hiệu để phân tích chính thức & lưu | `Dio` |

**Lý do thiết kế đáng nêu trong báo cáo:** app chỉ gửi **giá trị trung bình màu** chứ không upload video — vừa **bảo vệ quyền riêng tư**, vừa tránh việc nén video làm mất biên độ mạch (chỉ bằng một phần rất nhỏ % độ sáng).

### 3.2. Phía backend — thuật toán tính nhịp tim (`POST /heart-rate/analyze`)

> Nguồn: `health_api/app/ppg.py` (328 dòng), `app/api/health_router.py`, `app/schemas.py`. Các công thức POS/CHROM/periodogram/SNR nằm trong thư viện **rPPG-Toolbox** (không có trong repo, xem `VENDOR.md`) nên được mô tả theo bản gốc của thư viện đó.

#### 3.2.1. Nguyên tắc: backend **không tự phát minh thuật toán**

Module `ppg.py` chỉ làm 3 việc: (1) định dạng lại dữ liệu, (2) nội suy về lưới thời gian đều, (3) **bỏ phiếu** giữa nhiều kết quả độc lập. Phần ước lượng nhịp tim dùng lại các phương pháp đã công bố:

| Thành phần | Nguồn | Tài liệu tham khảo |
|---|---|---|
| **POS** (Plane-Orthogonal-to-Skin) | rPPG-Toolbox `POS_WANG.py` | Wang et al. (2017), *Algorithmic principles of remote PPG*, IEEE TBME 64(7) |
| **CHROM** (chrominance) | rPPG-Toolbox `CHROME_DEHAAN.py` | de Haan & Jeanne (2013), *Robust pulse rate from chrominance-based rPPG* |
| Tính tần số + SNR | rPPG-Toolbox `evaluation/post_process.py` (`_calculate_fft_hr`, `_calculate_SNR`) | Liu et al. (2023), *rPPG-Toolbox*, NeurIPS Datasets & Benchmarks |
| Đường “ngón tay” (hiện app không dùng) | **neurokit2** (Elgendi) | Elgendi et al. (2013), *Systolic peak detection...* |

#### 3.2.2. Dữ liệu đầu vào

```json
{ "source": "face", "times": [t0, t1, ...], "region_count": 3,
  "values": [R,G,B của vùng0, R,G,B của vùng1, R,G,B của vùng2, (frame kế tiếp)...],
  "context": "resting", "save": true }
```

- `values` được **làm phẳng theo thứ tự: frame → vùng → R,G,B**, rồi backend `reshape(frames, region_count, 3)`.
- Pydantic (`SignalAnalyze`) kiểm tra: `source ∈ {finger, face}`, ≥ 2 frame, ≤ 5000 frame, `region_count ∈ [1, 64]`, `len(values) == frames × regions × 3`, mọi `times` hữu hạn → sai thì trả lỗi 422.
- Một lần đo 30 s (bỏ 2 s đầu) ≈ 28 s × ~30 fps ≈ **~840 frame × 3 vùng × 3 kênh ≈ 7.500 số** (test `test_payload_size_is_practical_for_a_face_capture` kiểm tra kích thước payload hợp lý).

#### 3.2.3. Sơ đồ toàn bộ pipeline

```
(App)  camera frame ─► ML Kit tìm mắt ─► 3 vùng da (trán, má trái, má phải)
        ─► trung bình R,G,B mỗi vùng ─► SignalRecorder (30 s, bỏ 2 s đầu)
                                   │  POST /heart-rate/analyze
                                   ▼
(Server) ① Kiểm tra: ≥ 4 giây?  ── không ─► trả "Capture too short or unusable"
         ② Nội suy về lưới thời gian ĐỀU (fps thực đo = (N-1)/span)
         ③ fps ≥ 8?  ── không ─► không ước lượng
         ④ Với MỖI vùng (3) × MỖI phương pháp (POS, CHROM) = tối đa 6 "ứng viên":
              RGB ─► tín hiệu mạch BVP ─► FFT (periodogram) ─► BPM + SNR
         ⑤ BỎ PHIẾU: tìm nhóm lớn nhất các kết quả nằm trong ±5 BPM
         ⑥ BPM = trung vị của nhóm thắng;  SNR = trung vị SNR của nhóm
         ⑦ Trả về: bpm, snr_db, agreement/candidates, method, region, fps, amplitude, confidence
         ⑧ (nếu save=true) lưu HeartRateRecord vào DB + lưu bản ghi thô vào captures/
```

#### 3.2.4. Bước ① — Điều kiện đầu vào của `estimate()`

- `regions` phải có dạng `(frames, regions, 3)`; số frame của `times` và `regions` phải bằng nhau (sai → `ValueError`).
- Dưới 2 frame, hoặc thời lượng `times[-1] − times[0] < min_seconds = 4.0` giây → trả `None`.
- Endpoint chạy hàm này bằng `run_in_threadpool` vì lọc và FFT **tốn CPU**, không được chặn event loop của FastAPI.

#### 3.2.5. Bước ② — Nội suy về lưới thời gian đều (`resample_uniform`)

Frame camera **không đến đều đặn**, trong khi mọi phương pháp phía dưới giả định tần số lấy mẫu cố định.

1. Sắp xếp lại theo thời gian (`argsort`).
2. `span = t_cuối − t_đầu`; **fps thực = (N − 1) / span** (không tin vào “30 fps” danh nghĩa).
3. `count = floor(span × fps)`; lưới `grid = t_đầu + k / fps`, `k = 0..count−1`.
4. Nội suy tuyến tính `np.interp` **riêng cho từng kênh** (3 vùng × 3 màu = 9 kênh).

Test `test_tolerates_uneven_frame_delivery` và `test_rate_does_not_depend_on_frame_rate` xác nhận kết quả không phụ thuộc vào việc frame đến đều hay không.

#### 3.2.6. Bước ③ — Cổng tốc độ khung hình tối thiểu

`MIN_FPS = {"finger": 17, "face": 8}`. Dưới ngưỡng → trả `None` (thà từ chối còn hơn báo nhịp tim từ dữ liệu bị aliasing). Với mặt, chỉ cần fps đủ để băng tần trên 3 Hz không vượt Nyquist.

Lưu ý thực tế: **CHROM không chạy được dưới ~13 fps** (cửa sổ lọc `ceil(1.6×fps)` mẫu phải lớn hơn 21 mẫu mà `filtfilt` cần). Khi đó chỉ còn POS → mỗi vùng chỉ có 1 ứng viên (3 thay vì 6). Backend ghi `log.warning` thay vì im lặng bỏ qua, vì “số phiếu” lúc này mang ý nghĩa khác.

#### 3.2.7. Bước ④a — Ứng viên **POS** (Wang 2017)

Mục đích: tách thành phần **mạch** ra khỏi thay đổi **độ sáng chung** bằng cách chiếu màu RGB lên mặt phẳng vuông góc với hướng màu da.

Với cửa sổ trượt dài `l = ceil(1.6 × fps)` mẫu (≈ 1,6 giây):

1. **Chuẩn hóa theo trung bình cửa sổ:** `Cn = RGB[m:n] / mean(RGB[m:n])` (từng kênh) → triệt tiêu độ sáng nền và màu da riêng từng người.
2. **Chiếu lên 2 trục** bằng ma trận cố định:
   `S1 = G_n − B_n`  và  `S2 = −2·R_n + G_n + B_n`  (ma trận `[[0,1,−1],[−2,1,1]]`).
3. **Điều chỉnh theo độ lệch chuẩn (alpha-tuning):** `h = S1 + (σ(S1) / σ(S2)) · S2`.
4. Trừ trung bình: `h ← h − mean(h)`.
5. **Cộng chồng (overlap-add)** `h` vào tín hiệu tổng `H[m:n]` khi cửa sổ trượt từng mẫu.
6. Sau cùng: **detrend** (tham số làm mượt 100) để bỏ trôi chậm, rồi **lọc thông dải Butterworth bậc 1, 0,75–3 Hz** bằng `filtfilt` (lọc hai chiều, không lệch pha).

Kết quả là tín hiệu thể tích máu **BVP** (Blood Volume Pulse).

#### 3.2.8. Bước ④b — Ứng viên **CHROM** (de Haan & Jeanne 2013)

Dựa trên mô hình phản xạ da: tạo hai tín hiệu **sắc độ (chrominance)** triệt tiêu thành phần phản xạ gương (độ sáng).

Cửa sổ dài `WinL = ceil(1.6 × fps)` (làm chẵn), **chồng lấn 50%**:

1. Chuẩn hóa: `R_n, G_n, B_n = RGB / mean(RGB)` trong cửa sổ.
2. Hai tín hiệu sắc độ:
   `X = 3·R_n − 2·G_n`
   `Y = 1,5·R_n + G_n − 1,5·B_n`
3. **Lọc thông dải Butterworth bậc 3, 0,7–2,5 Hz** (`filtfilt`) cho cả `X` và `Y` → `Xf`, `Yf`.
4. Hệ số `α = σ(Xf) / σ(Yf)`; tín hiệu cửa sổ `S = Xf − α·Yf`.
5. Nhân với **cửa sổ Hann** (`hanning(WinL)`) rồi **cộng chồng** các cửa sổ để ghép thành BVP liên tục.

> POS và CHROM **bù trừ** nhau: cả hai đều khử độ sáng chung nhưng bằng hai cách khác nhau → khi cùng ra một nhịp thì đáng tin hơn.

**Một chi tiết kỹ thuật đáng nêu:** cả hai hàm gốc nhận *video* và tự lấy trung bình mỗi frame. Vì app đã gửi sẵn trung bình màu, backend đưa mỗi mẫu vào dưới dạng **“frame 1×1 pixel”** (`reshape(N,1,1,3)`) — trung bình của một pixel chính là pixel đó → dùng nguyên bản thuật toán đã công bố, **không phải cài lại**. Ngoài ra, NumPy 2 đã xóa `np.mat` mà POS còn gọi, nên có một dòng `np.mat = np.asmatrix` làm shim tương thích.

#### 3.2.9. Bước ④c — Từ BVP ra **BPM**: phổ tần số (periodogram)

Hàm `_calculate_fft_hr` (rPPG-Toolbox):

1. Zero-padding tới **lũy thừa 2 kế tiếp** của độ dài tín hiệu (`nfft`).
2. `scipy.signal.periodogram(bvp, fs=fps, nfft=nfft, detrend=False)` → mật độ công suất theo tần số.
3. Chỉ giữ tần số trong băng **0,75–3,0 Hz** (= **45–180 BPM**: `MIN_BPM = 45`, `MAX_BPM = 180`).
4. Tần số có công suất lớn nhất (`argmax`) × 60 = **BPM**.

Độ phân giải: 28 s → độ phân giải thật `1/T ≈ 0,036 Hz ≈ 2,1 BPM`; zero-padding chỉ nội suy đường cong phổ cho mịn hơn. Đây cũng là lý do app **tăng thời gian đo từ 15 lên 30 s**: cửa sổ 13 s chỉ phân giải ~4,6 BPM và mạch dễ bị chìm dưới nhịp nuốt/chớp mắt (ghi chú trong `signal_recorder.dart`).

Tín hiệu bị loại (trả `None`) nếu: dưới 16 mẫu, có giá trị không hữu hạn, độ lệch chuẩn ≤ 1e-12 (tín hiệu phẳng), hoặc BPM ngoài [45, 180].

#### 3.2.10. Bước ④d — Tính **SNR (dB)**

Hàm `_calculate_SNR` (rPPG-Toolbox), lấy BPM vừa tìm được làm chuẩn:

- `f1 = BPM / 60` (hài bậc 1), `f2 = 2·f1` (hài bậc 2).
- Độ rộng cửa sổ quanh mỗi hài: **±6 BPM (±0,1 Hz)**.
- `P_signal = Σ công suất trong cửa sổ quanh f1 + Σ công suất quanh f2`.
- `P_noise = Σ công suất còn lại trong băng 0,75–3 Hz`.
- **`SNR = 10 · log10(P_signal / P_noise)`** (dB).

SNR cao = năng lượng tập trung quanh một nhịp rõ rệt (và hài bậc 2 của nó), thấp/âm = phổ phân tán như nhiễu. Test `test_noise_scores_far_below_a_real_pulse` và `test_a_drifting_baseline_scores_far_below_a_real_pulse` kiểm tra nhiễu và trôi nền đều cho SNR thấp hơn hẳn mạch thật.

#### 3.2.11. Bước ⑤–⑥ — **Bỏ phiếu theo nhóm đồng thuận** (đóng góp riêng của dự án)

Mỗi cặp (vùng, phương pháp) cho một “ứng viên” `(tên, vùng, bpm, snr, biên độ, chất lượng)`. Với face thường có **6 ứng viên** (3 vùng × POS, CHROM).

Thuật toán chọn:

1. Với từng ứng viên, tạo **nhóm** = mọi ứng viên có BPM cách nó ≤ `AGREEMENT_BPM = 5`.
2. Chọn **nhóm đông nhất**.
3. Nếu nhiều nhóm đông bằng nhau → chọn nhóm có **trung vị gần trung vị toàn bộ nhất** (*không* chọn theo SNR cao nhất).
4. **`bpm` = trung vị BPM của nhóm thắng.**
5. **`snr_db` = trung vị SNR của nhóm thắng.**
6. “Ứng viên đại diện” (`method`, `region`, `amplitude`, `quality`) = ứng viên có **SNR cao nhất trong nhóm thắng**, để các nhãn hiển thị trỏ vào thứ thực sự ủng hộ kết quả.
7. `agreement` = kích thước nhóm thắng; `candidates` = tổng số ứng viên hợp lệ → app hiển thị dạng “4/6”.

**Vì sao không dùng cách đơn giản hơn** (số liệu ghi trong code, đo trên 6 lần đo so với đồng hồ đeo tay):

| Cách chọn | Sai số trung bình | Sai số tệ nhất |
|---|---|---|
| **Nhóm đồng thuận (đang dùng)** | **2,6 BPM** | **4,6 BPM** |
| Trung vị của tất cả | 5,7 BPM | 19 BPM |
| Chọn SNR cao nhất | 14,9 BPM | 43 BPM |

Trung vị của một tập rời rạc có thể rơi vào giữa hai kết quả mà *không phương pháp nào* đã báo (một lần báo 69 BPM khi không ai nói gần số đó); còn chọn SNR cao nhất từng chọn nhầm 45 BPM khi đồng hồ đọc 88.

> ⚠ **Cảnh báo trung thực khi viết báo cáo:** đây là bằng chứng trên **mẫu rất nhỏ (6–8 lần đo, 1–3 điện thoại)**. Chính tác giả ghi trong code rằng “tất cả ứng viên đồng thuận” chỉ mới đi kèm sai số < 4 BPM, còn “ít ứng viên đồng thuận” **không** có nghĩa là sai (một lần lệch 0,3 BPM chỉ có 2/6 đồng thuận). Không nên tuyên bố độ chính xác thống kê.

#### 3.2.12. Bước ⑦ — `confidence` và việc **không có ngưỡng từ chối**

- `confidence = clip((snr_db + 10) / 20, 0, 1)` (nhân thêm `quality` nếu là đường ngón tay). **Chỉ để vẽ thanh tiến trình, không phải bằng chứng.**
- **Cố ý không có ngưỡng chấp nhận/từ chối theo SNR.** Phiên bản đầu có ngưỡng SNR hiệu chỉnh trên tín hiệu tổng hợp tự sinh → vượt qua test của chính mình nhưng **từ chối mọi lần đo thật**. Cả rPPG-Toolbox lẫn neurokit2 đều không có cổng như vậy. Nay API luôn trả BPM kèm `snr_db` và `agreement/candidates`; việc đánh giá độ tin cậy phải dựa trên so sánh với thiết bị tham chiếu (đồng hồ).
- Chỉ trả `bpm = null` + `message = "Capture too short or unusable"` khi không thể tạo ra tín hiệu nào (quá ngắn, fps quá thấp, tín hiệu phẳng...).

#### 3.2.13. Phản hồi của API

| Trường | Ý nghĩa |
|---|---|
| `bpm` | Nhịp tim (làm tròn số nguyên); `null` nếu capture không dùng được |
| `snr_db` | SNR (trung vị nhóm thắng) |
| `agreement`, `candidates` | Số kết quả đồng thuận / tổng số kết quả |
| `method`, `region` | Phương pháp (`pos`/`chrom`) và chỉ số vùng của ứng viên đại diện |
| `fps` | Tốc độ khung hình thực đo |
| `amplitude` | Biên độ BVP (max − min) của ứng viên đại diện |
| `confidence` | 0–1, chỉ để hiển thị |
| `quality` | Chỉ có ở đường ngón tay (template-match SQI); `null` với mặt |
| `message` | Thông báo khi thất bại |

#### 3.2.14. Hai chế độ gọi: “đo thử” và “đo chính thức”

| | Live poll | Phân tích cuối |
|---|---|---|
| Khi nào | Mỗi 2 s, sau giây thứ 8 của dữ liệu, dừng khi tiến độ > 90% | Khi đủ 30 s |
| `save` | `false` | `true` (mặc định) |
| Ghi DB? | Không | Có — `HeartRateRecord(bpm, confidence, measurement_duration, context)` |
| Lưu bản thô? | Không | Có — `captures/<thời gian>-face.json` |
| Timeout (app) | 10 s gửi / 15 s nhận | 30 s gửi / 60 s nhận |

Bản thô (`times`, `values`, kết quả) được lưu tối đa **50 file** mới nhất, tắt bằng biến môi trường `HEARTBEAT_SAVE_CAPTURES=0`. Mục đích: phân tích offline bằng `tools/inspect_capture.py` khi một lần đo thất bại.

#### 3.2.15. Công cụ đánh giá offline (thư mục `tools/`)

| File | Công dụng |
|---|---|
| `calibrate_snr.py` | Sinh tín hiệu tổng hợp (mạch có sóng hài, trôi nền, nhiễu; hệ số phản xạ da `[0.33, 0.77, 0.53]` – xanh lá nhạy nhất theo Wang 2017) để xem mạch thật vs nhiễu tách nhau thế nào trong SNR. **Không dùng làm ngưỡng.** |
| `compare_captures.py` | Chấm điểm các capture đã lưu so với nhịp tim đọc từ **đồng hồ** (bảng `REFERENCE`); gọi trực tiếp `app.ppg` để không lệch với code đang chạy |
| `inspect_capture.py` | Soi một capture: trôi nền, nhiễu, có mạch hay không |

#### 3.2.16. Đường “ngón tay” (backend hỗ trợ, app hiện không dùng)

Khi `source = "finger"` (ánh sáng **xuyên qua** ngón tay → tín hiệu PPG tiếp xúc, phương pháp chrominance không áp dụng):

1. Lấy kênh **Red** và **Green** (mỗi kênh một ứng viên), **đảo dấu** (`−x`) vì máu nhiều hấp thụ nhiều → camera thấy tín hiệu ngược so với PPG lâm sàng.
2. `neurokit2.ppg_clean(method="elgendi")` — lọc thông dải.
3. `neurokit2.ppg_findpeaks(method="elgendi")` — tìm đỉnh tâm thu.
4. Nếu ≥ 4 đỉnh: `ppg_quality(method="templatematch")` → **SQI** (độ giống nhau giữa các nhịp, trung bình).
5. Tín hiệu đã làm sạch được đưa qua **cùng** bước periodogram + SNR + bỏ phiếu như đường mặt.

## 4. GIAO TIẾP CLIENT ↔ SERVER (REST API)

| Thuộc tính | Giá trị |
|---|---|
| Kiểu API | **RESTful**, JSON |
| Base URL (production) | `https://toannd.work/api/v1` |
| Base URL (dev local) | `http://192.168.100.84:8000/api/v1` (IP LAN máy dev, port 8000 — cổng mặc định của Uvicorn) |
| Giao thức | HTTPS (production), HTTP cleartext (chỉ dev) |
| Xác thực | **JWT Bearer** trong header `Authorization` |
| Lưu token | `flutter_secure_storage` (khóa `access_token`) |
| HTTP client | `dio` 5.11.1 |
| Lỗi | Server trả `{"detail": "..."}` (chuẩn FastAPI `HTTPException`); app đọc `e.response.data['detail']` |
| Proxy | **Cloudflare** đứng trước API (trả 403 error 1010 nếu request không có User-Agent; Dio gửi UA mặc định của Dart nên hợp lệ) |
| Timeout đặc biệt | `/heart-rate/analyze`: live poll send 10s / receive 15s; phân tích cuối send 30s / receive 60s |

### 4.1. Danh sách endpoint mà app **thực sự gọi** (đã kiểm chứng từ code)

| Nhóm | Method | Endpoint | Màn hình gọi | Mô tả |
|---|---|---|---|---|
| **Auth** | POST | `/auth/register` | Auth | Đăng ký (`email`, `password`, `full_name`) |
| | POST | `/auth/login` | Auth | Đăng nhập, nhận `access_token` |
| | GET | `/auth/me` | Auth, Dashboard, Profile | Lấy thông tin user hiện tại / kiểm tra token |
| **Dashboard** | GET | `/dashboard` | Dashboard | Dữ liệu tổng hợp màn hình chính |
| **Nhịp tim** | POST | `/heart-rate/analyze` | Measure | Phân tích tín hiệu rPPG (`save: false` = chỉ xem thử, không lưu) |
| | GET | `/heart-rate?limit=N` | Dashboard (30), History (100) | Danh sách các lần đo |
| **Cân nặng** | GET | `/weight?limit=N` | Weight (60), Dashboard (30) | Lịch sử cân nặng |
| | POST | `/weight` | Weight | Ghi nhận cân nặng mới |
| **Hồ sơ sức khỏe** | GET | `/health-profile` | Weight, Profile | Chiều cao, cân nặng, nhóm máu... |
| | PUT | `/health-profile` | Profile | Cập nhật hồ sơ |
| **Dinh dưỡng** | GET | `/nutrition/summary?days=14` | Dashboard, Meals | Tổng hợp calo/macro 14 ngày + mục tiêu |
| | GET | `/meals` | Meals | Danh sách bữa ăn |
| | POST | `/meals` | Meals | Thêm bữa ăn (`name`, `calories`, `meal_type`, `protein_g`, `carbs_g`, `fat_g`) |
| | DELETE | `/meals/{id}` | Meals | Xóa bữa ăn |
| **Mục tiêu** | GET | `/goals` | Goals | Danh sách mục tiêu |
| | POST | `/goals` | Goals | Tạo mục tiêu (có `deadline` dạng `yyyy-MM-dd`) |
| | PUT | `/goals/{id}` | Goals | Cập nhật tiến độ (`current_value`) |
| **Nhắc nhở** | GET | `/reminders` | Reminders | Danh sách nhắc nhở |
| | POST | `/reminders` | Reminders | Tạo nhắc nhở |
| | DELETE | `/reminders/{id}` | Reminders | Xóa nhắc nhở |

**Tổng cộng: 21 lời gọi API / ~18 endpoint khác nhau.** Danh sách đầy đủ phía server (kể cả endpoint app chưa gọi) ở mục 5.4.

> **Chênh lệch giữa thiết kế và thực tế:** `DESIGN.html` đặt đường dẫn kiểu `/users/me`, `/stats/dashboard`, `/health/weight`... còn app thực tế gọi `/auth/me`, `/dashboard`, `/weight`, `/health-profile`. Ngoài ra thiết kế có `refresh`, `logout`, `forgot-password`... nhưng **backend thực tế cũng không triển khai**. Module **dinh dưỡng (`/meals`, `/nutrition/summary`)** có trong app nhưng **không có trong tài liệu thiết kế**. Khi viết báo cáo nên lấy bảng ở mục 4.1 làm chuẩn.

---

## 5. SERVER — FastAPI (Python) — repo `health_api`

> Nguồn: source thật trong thư mục `health_api/` (đã đọc `main.py`, `app/*.py`, `app/api/*.py`, `Dockerfile`, `fly.toml`, `requirements.txt`, `tests/`, `tools/`). Quy mô: **~2.060 dòng Python** (tính cả test và tools).

### 5.1. Công nghệ backend (thực tế)

| Thành phần | Công nghệ | Chi tiết trong code |
|---|---|---|
| Ngôn ngữ / runtime | **Python 3.14** (`python:3.14-slim` trong Dockerfile) | |
| Web framework | **FastAPI** (`title="HeartBeat API"`, `version="1.0.0"`) | Async; tự sinh OpenAPI/Swagger tại `/docs` |
| ASGI server | **Uvicorn** (`uvicorn[standard]`) | `uvicorn main:app --host 0.0.0.0 --port 8080` |
| Validation / schema | **Pydantic v2** (`pydantic[email]`) | `model_validator` kiểm tra payload tín hiệu; `EmailStr` |
| ORM | **SQLAlchemy 2.x async** (`sqlalchemy[asyncio]`) | `DeclarativeBase`, `Mapped[...]`, `mapped_column`, `async_sessionmaker` |
| Driver DB | **aiosqlite** | Kết nối SQLite bất đồng bộ |
| Cơ sở dữ liệu | **SQLite** (file `health.db`) | `sqlite+aiosqlite:///./health.db` (dev), `/app/data/health.db` (production, volume) |
| Tạo bảng | `Base.metadata.create_all` lúc khởi động (`lifespan`) | **Không dùng Alembic** |
| Xác thực | **JWT HS256** bằng `python-jose[cryptography]` | Claim `sub` = user id, `exp` = 60 phút |
| Băm mật khẩu | **bcrypt** (gọi trực tiếp `bcrypt.hashpw/checkpw`) | `passlib[bcrypt]` có trong requirements nhưng code không import |
| OAuth2 | `OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")` | Dùng để lấy Bearer token và hiện nút Authorize trên Swagger |
| Form | `python-multipart` | Phụ thuộc của OAuth2 form |
| CORS | `CORSMiddleware` | `allow_origins=["*"]`, mọi method/header |
| Tính toán số | **NumPy**, **SciPy** (`signal.periodogram`, `butter`, `filtfilt`, `interp`) | Xử lý tín hiệu |
| PPG tiếp xúc | **neurokit2** | Đường “ngón tay” (Elgendi) |
| rPPG | **rPPG-Toolbox** (clone git vào `vendor_rppg/`, ~660 MB, không đưa vào git) | POS, CHROM, FFT-HR, SNR |
| Phụ thuộc kéo theo | `opencv-python-headless`, `scikit-image`, `torch` | OpenCV/scikit-image chỉ vì toolbox import ở mức module; **torch cho đường GPU, ứng dụng hiện không gọi tới mô hình deep-learning nào** |
| Xử lý CPU nặng | `fastapi.concurrency.run_in_threadpool` | Đẩy phân tích tín hiệu ra khỏi event loop |
| Test | **pytest** | 3 file: `test_ppg.py`, `test_analyze_endpoint.py`, `test_nutrition.py` |
| Logging | `logging.basicConfig(INFO)` | Logger `heartbeat.ppg`, `heartbeat.captures` |

### 5.2. Cấu trúc project backend (thực tế)

```
health_api/
├── main.py                  # Entry: FastAPI app, CORS, lifespan(init_db), include 2 router
├── requirements.txt
├── Dockerfile               # python:3.14-slim, port 8080
├── fly.toml                 # Cấu hình Fly.io
├── .dockerignore
├── VENDOR.md                # Hướng dẫn clone rPPG-Toolbox vào vendor_rppg/
├── app/
│   ├── config.py            # Settings: DATABASE_URL, SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES
│   ├── database.py          # async engine, session, Base, get_db, init_db
│   ├── models.py            # 7 bảng ORM
│   ├── schemas.py           # Pydantic request/response
│   ├── auth.py              # hash/verify bcrypt, tạo JWT, get_current_user (Depends)
│   ├── ppg.py               # ★ Thuật toán nhịp tim (328 dòng)
│   ├── nutrition.py         # Mifflin–St Jeor: calo & macro mục tiêu
│   ├── captures.py          # Lưu bản thô các lần đo (tối đa 50) để phân tích offline
│   └── api/
│       ├── auth_router.py   # /api/v1/auth/*
│       └── health_router.py # /api/v1/* (mọi thứ còn lại)
├── tests/                   # conftest + 3 file test
└── tools/                   # calibrate_snr.py, compare_captures.py, inspect_capture.py
```

Kiến trúc: **Router → (Pydantic schema) → ORM/thuật toán**, dùng **Dependency Injection** (`Depends(get_db)`, `Depends(get_current_user)`). Khác thiết kế ban đầu: **không có tầng `services/`**; logic nằm trong router và hai module `ppg.py`, `nutrition.py`.

### 5.3. Cơ sở dữ liệu — SQLite *(thay cho PostgreSQL trong thiết kế)*

Khóa chính là `String(36)` chứa UUID sinh bằng `uuid.uuid4()`. Mọi bảng dữ liệu đều có `user_id` (index) — **không khai báo FOREIGN KEY** thực sự, việc ràng buộc làm ở tầng ứng dụng.

| Bảng | Cột | Ghi chú |
|---|---|---|
| `users` | id, email (unique, index), password_hash, full_name, date_of_birth, gender, is_active, created_at | Ngày sinh + giới tính dùng tính tuổi cho calo |
| `health_profiles` | id, user_id, height_cm, weight_kg, bmi, blood_type, updated_at | BMI tự tính: `weight / (height/100)²`, làm tròn 1 chữ số; tự tạo hồ sơ rỗng khi GET lần đầu |
| `heart_rate_records` | id, user_id, bpm, confidence, measurement_duration, context, measured_at | `context` mặc định `resting` |
| `weight_records` | id, user_id, weight_kg, bmi, recorded_at | |
| `reminders` | id, user_id, type, title, schedule_cron, is_enabled | |
| `health_goals` | id, user_id, type, target_value, current_value, unit, deadline, status | `status` mặc định `active` |
| `meal_records` | id, user_id, name, calories, meal_type, protein_g, carbs_g, fat_g, eaten_at (index) | `meal_type`: breakfast / lunch / dinner / snack |

### 5.4. Danh sách endpoint của backend (đã kiểm chứng từ router)

Tất cả nằm dưới `/api/v1`. Trừ `register` và `login`, mọi endpoint đều yêu cầu Bearer JWT.

| Nhóm | Method | Path | Mô tả | App có gọi? |
|---|---|---|---|---|
| Hệ thống | GET | `/` | `{"message": "HeartBeat API is running"}` | — |
| Auth | POST | `/auth/register` | 201; email trùng → 400 | ✔ |
| | POST | `/auth/login` | Body JSON `{email, password}` → `{access_token}`; sai → 401 | ✔ |
| | GET | `/auth/me` | Thông tin user hiện tại | ✔ |
| Hồ sơ | GET | `/health-profile` | Tự tạo nếu chưa có | ✔ |
| | PUT | `/health-profile` | Cập nhật chiều cao/cân nặng/nhóm máu, tự tính BMI | ✔ |
| Nhịp tim | POST | `/heart-rate/analyze` | ★ Phân tích tín hiệu rPPG (mục 3.2) | ✔ |
| | POST | `/heart-rate` | Lưu tay một kết quả (bpm, …) | ✘ |
| | GET | `/heart-rate?limit&offset` | Danh sách (mới nhất trước) | ✔ |
| | GET | `/heart-rate/latest` | Lần đo gần nhất | ✘ |
| Dinh dưỡng | POST | `/meals` | Thêm bữa ăn | ✔ |
| | GET | `/meals?day=` | Danh sách, lọc theo ngày | ✔ |
| | DELETE | `/meals/{id}` | Xóa (204) | ✔ |
| | GET | `/nutrition/summary?days=` | Hôm nay + lịch sử `days` ngày (kẹp 1–90) + mục tiêu calo | ✔ |
| Cân nặng | POST | `/weight` | Ghi cân nặng | ✔ |
| | GET | `/weight?limit=` | Lịch sử | ✔ |
| Nhắc nhở | POST / GET / DELETE | `/reminders`, `/reminders/{id}` | CRUD (không có sửa/toggle) | ✔ |
| Mục tiêu | POST / GET | `/goals` | Tạo / liệt kê | ✔ |
| | PUT | `/goals/{id}` | Cập nhật `current_value` | ✔ |
| Dashboard | GET | `/dashboard` | `latest_bpm`, `avg_bpm_7d`, `current_bmi`, `active_goals`, `measurement_count` | ✔ |

### 5.5. Module dinh dưỡng — công thức **Mifflin–St Jeor (1990)**

`app/nutrition.py` tính calo/macro mục tiêu từ hồ sơ người dùng:

- **Tuổi** tính theo năm tròn từ `date_of_birth` (hợp lệ khi 0 < tuổi < 130).
- **BMR (kcal/ngày)** = `10·cân_nặng(kg) + 6,25·chiều_cao(cm) − 5·tuổi` rồi **+5** (nam), **−161** (nữ), **−78** (chưa rõ giới → lấy điểm giữa để sai lệch ~80 kcal hai phía thay vì sai một chiều).
- **Calo mục tiêu = BMR × hệ số vận động:** sedentary 1,2 · **light 1,375 (mặc định)** · moderate 1,55 · active 1,725 · very_active 1,9.
- **Macro:** đạm 20% (4 kcal/g), tinh bột 50% (4 kcal/g), béo 30% (9 kcal/g).
- Trả kèm đầu vào (`from_weight_kg`, `from_height_cm`, `from_age`, `from_gender`) để app nói rõ con số được tính từ đâu, vì sai số có thể vài trăm kcal. Hồ sơ thiếu dữ liệu → `target = null`.
- `nutrition/summary` **điền đủ cả những ngày trống** (0 kcal) để biểu đồ không “khép khoảng trống” gây hiểu nhầm.

### 5.6. Xác thực & bảo mật phía server

1. `register`: kiểm tra email trùng → `bcrypt.hashpw(password, gensalt())` → lưu.
2. `login`: `bcrypt.checkpw` → `jwt.encode({"sub": user_id, "exp": now+60 phút}, SECRET_KEY, HS256)`.
3. `get_current_user`: giải mã JWT → đọc `sub` → truy vấn `users`; sai/hết hạn/không tìm thấy → **401**.
4. `SECRET_KEY` đọc từ biến môi trường, mặc định `dev-secret-change-in-production`.

---

## 6. HẠ TẦNG & TRIỂN KHAI (thực tế)

| Thành phần | Công nghệ / cấu hình | Nguồn |
|---|---|---|
| Nền tảng chạy | **Fly.io** — app `health-api-thunt`, region `sin` (Singapore) | `fly.toml` |
| Container | **Docker** (`python:3.14-slim`, `pip install -r requirements.txt`, `COPY . .`, port 8080) | `Dockerfile` |
| HTTPS | `force_https = true` (Fly kết thúc TLS) | `fly.toml` |
| Tự động tắt/bật | `auto_stop_machines = 'stop'`, `auto_start_machines = true`, `min_machines_running = 0` → **máy tắt khi rảnh**, lần gọi đầu tiên sẽ chậm (cold start) | `fly.toml` |
| Tài nguyên máy | 1 shared vCPU, **256 MB RAM** | `fly.toml` |
| Lưu trữ | Volume `health_data` gắn vào `/app/data` chứa file SQLite | `fly.toml` |
| Biến môi trường | `DATABASE_URL=sqlite+aiosqlite:////app/data/health.db` | `fly.toml` |
| Domain / proxy | `toannd.work` qua **Cloudflare** (URL trong `constants.dart`; ghi chú về lỗi 1010) | app Flutter |
| Không có | Nginx, Redis, Firebase/FCM, Alembic, docker-compose | — |

**Điểm cần kiểm tra trước khi viết “đã triển khai ổn định”:**
- `vendor_rppg/` (~660 MB) **không nằm trong git** nhưng `Dockerfile` làm `COPY . .` và `.dockerignore` không loại nó → muốn image có thuật toán phải clone thư mục này trước khi build. Nếu thiếu, `ppg.py` sẽ lỗi import khi khởi động.
- `requirements.txt` có `torch`, `opencv`, `scikit-image` — nặng so với máy **256 MB RAM**; nên đo thực tế mức RAM khi chạy.
- Tên miền `toannd.work` (Cloudflare) và app Fly.io là hai thông tin từ hai nơi khác nhau; việc hai thứ trỏ vào nhau là **suy luận hợp lý**, repo không ghi rõ cấu hình DNS.

---

## 7. BẢO MẬT & QUYỀN RIÊNG TƯ

### 7.1. Đã triển khai (kiểm chứng trong code)

| Biện pháp | Chi tiết |
|---|---|
| Mật khẩu | **bcrypt** có salt ngẫu nhiên |
| Phiên đăng nhập | JWT HS256, hết hạn sau **60 phút** |
| Lưu token trên máy | `flutter_secure_storage` (Keychain/Keystore) |
| Phân quyền dữ liệu | Mọi truy vấn lọc theo `user_id` của người dùng hiện tại |
| Kiểm tra đầu vào | Pydantic (giới hạn số frame ≤ 5000, `region_count` 1–64, độ dài `values` khớp) |
| HTTPS | Fly.io `force_https` + Cloudflare |
| ORM | SQLAlchemy dùng tham số hóa → chống SQL injection |
| Riêng tư dữ liệu sinh trắc | **Không upload video/ảnh mặt**, chỉ gửi trung bình RGB của 3 vùng da; ML Kit chạy trên máy |
| Lưu bản thô | Chỉ gồm trung bình màu + thời gian, không có danh tính, tối đa 50 file, tắt được bằng env var |

### 7.2. Chưa có (khác với `DESIGN.html`)

Refresh token / logout / quên mật khẩu, rate limiting (100 req/phút), CORS whitelist, mã hóa AES-256 at rest, certificate pinning, phát hiện root/jailbreak, obfuscation, xóa tài khoản.

### 7.3. Rủi ro & hạn chế (nên đưa vào mục “hạn chế / hướng phát triển”)

| # | Vấn đề | Chỗ trong code |
|---|---|---|
| 1 | `SECRET_KEY` có giá trị mặc định công khai nếu quên đặt biến môi trường — ai biết sẽ **tự ký được JWT** | `app/config.py` |
| 2 | `CORS allow_origins=["*"]` kèm `allow_credentials=True` quá rộng | `main.py` |
| 3 | Không có rate limit trên `/auth/login` → có thể dò mật khẩu | `auth_router.py` |
| 4 | Token 60 phút nhưng app chưa có refresh → hết hạn là phải đăng nhập lại | cả hai repo |
| 5 | `usesCleartextTraffic="true"` trên Android | `AndroidManifest.xml` |
| 6 | Bản release Android ký bằng **debug key** | `build.gradle.kts` |
| 7 | `localApiBaseUrl` hard-code IP LAN | `constants.dart` |
| 8 | SQLite + `create_all`: không có migration, khó nâng cấp schema; một file DB trên một máy → khó mở rộng | `database.py`, `fly.toml` |
| 9 | Không có FOREIGN KEY giữa các bảng | `models.py` |
| 10 | `OAuth2PasswordBearer` khai báo nhưng `login` nhận JSON chứ không phải form → nút Authorize của Swagger không dùng được với endpoint login | `auth.py`, `auth_router.py` |
| 11 | Độ chính xác nhịp tim mới được đối chiếu trên **vài lần đo** với đồng hồ; chưa có đánh giá thống kê (MAE, Bland–Altman) | `tools/compare_captures.py` |
| 12 | Ứng dụng là công cụ tham khảo, **không phải thiết bị y tế** | — |

---

## 8. SO SÁNH: THIẾT KẾ BAN ĐẦU (`DESIGN.html`) vs. THỰC TẾ

| Hạng mục | Theo thiết kế | Thực tế |
|---|---|---|
| Phương pháp đo | PPG ngón tay + flash, camera sau | **rPPG khuôn mặt**, camera trước, 3 vùng da (backend vẫn hỗ trợ ngón tay) |
| Nơi xử lý tín hiệu | Trên máy (Butterworth bậc 4 + dò đỉnh, Dart) | **Trên server** (POS + CHROM + periodogram + bỏ phiếu) |
| Cơ sở dữ liệu | PostgreSQL 15 | **SQLite** (aiosqlite) |
| Migration | Alembic | `create_all` |
| Cache / hàng đợi | Redis | Không có |
| Reverse proxy | Nginx | Fly.io proxy + Cloudflare |
| Push | Firebase FCM | Không có |
| Docker | Docker + docker-compose | Dockerfile (không có compose) |
| Triển khai | Tự host | **Fly.io (Singapore)** |
| Auth | JWT + refresh + OAuth2 | JWT 60 phút, không refresh |
| Cấu trúc backend | `services/`, `schemas/`, `models/`, `core/` | Phẳng: `models.py`, `schemas.py`, `auth.py`, `ppg.py`, `nutrition.py`, 2 router |
| URL API | `/users/me`, `/stats/dashboard`, `/health/weight` ... | `/auth/me`, `/dashboard`, `/weight`, `/health-profile` |
| Nhắc nhở | CRUD + toggle + cron scheduler + push | Chỉ CRUD, **không có bộ lập lịch thực sự** (chỉ lưu chuỗi cron) |
| Dinh dưỡng | Không có | **Có** (meals, Mifflin–St Jeor) |
| Flutter | go_router, sqflite, firebase_messaging, freezed, nhiều BLoC | Chỉ `AuthBloc`; không có các gói trên (go_router khai báo nhưng chưa dùng) |

---

## 9. BẢNG TỔNG HỢP CÔNG NGHỆ (DÙNG ĐỂ DÁN VÀO BÁO CÁO)

| Tầng | Công nghệ |
|---|---|
| **Mobile framework** | Flutter ≥ 3.44, Dart 3.13 |
| **UI** | Material 3, Google Fonts (Nunito Sans), fl_chart 0.70.2 |
| **State management** | flutter_bloc 9.1.1 (BLoC) |
| **Networking (client)** | Dio 5.11.1, REST/JSON, JWT Bearer |
| **Lưu trữ cục bộ** | flutter_secure_storage 9.2.4 |
| **Camera / AI on-device** | camera 0.12.1 (CameraX), Google ML Kit Face Detection 0.12.0 |
| **i18n** | flutter_localizations, intl 0.20.3 (vi, en) |
| **Native** | Kotlin + Gradle KTS + Java 17 (Android); Swift + Xcode (iOS) |
| **Backend** | Python 3.14, FastAPI, Uvicorn, Pydantic v2 |
| **ORM / DB** | SQLAlchemy 2 (async) + aiosqlite, SQLite |
| **Bảo mật** | JWT (python-jose, HS256), bcrypt, OAuth2PasswordBearer, HTTPS |
| **Xử lý tín hiệu** | NumPy, SciPy, neurokit2, rPPG-Toolbox (POS, CHROM, periodogram, SNR) |
| **Phụ thuộc kéo theo** | OpenCV (headless), scikit-image, PyTorch |
| **Dinh dưỡng** | Công thức Mifflin–St Jeor |
| **Test** | flutter_test (3 file); pytest (3 file backend) |
| **Triển khai** | Docker, Fly.io (region sin, 1 shared vCPU / 256 MB, volume SQLite), Cloudflare (domain) |
| **Thuật toán nhịp tim** | ROI theo landmark mắt → trung bình RGB → nội suy lưới đều → POS & CHROM × 3 vùng → periodogram (45–180 BPM) → SNR → bỏ phiếu nhóm ±5 BPM → trung vị |

---

## 10. GỢI Ý CẤU TRÚC BÁO CÁO

1. Giới thiệu đề tài & mục tiêu
2. Phân tích yêu cầu / chức năng (mục 1)
3. Kiến trúc hệ thống (mục 1.1, 4)
4. Công nghệ Client — Flutter & thư viện (mục 2)
5. Thuật toán đo nhịp tim rPPG (mục 3)
6. Thiết kế API & Backend FastAPI (mục 4, 5)
7. Cơ sở dữ liệu (mục 5.3)
8. Bảo mật (mục 7)
9. Kiểm thử (3 file test trong `test/`)
10. Đánh giá, hạn chế & hướng phát triển (mục 7.3, 8)
