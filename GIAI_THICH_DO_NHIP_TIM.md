# Ứng dụng HeartBeat đo nhịp tim bằng camera như thế nào?

*Bản giải thích đơn giản dành cho học sinh. Bản chi tiết kỹ thuật nằm ở `TECH_STACK_REPORT.md`.*

---

## 1. Ý tưởng chính (nói trong 30 giây)

Mỗi lần tim đập, máu được bơm đi khắp cơ thể, **kể cả những mạch máu rất nhỏ dưới da mặt**. Máu hấp thụ ánh sáng xanh lá, nên khi có nhiều máu hơn thì da hấp thụ nhiều ánh sáng hơn, và màu da **thay đổi cực kỳ nhẹ** (mắt thường không thấy được).

Camera điện thoại thì nhìn ra được sự thay đổi đó. Ứng dụng quay mặt bạn khoảng 30 giây, theo dõi màu da lên xuống theo từng nhịp, rồi **đếm xem màu da "đập" bao nhiêu lần mỗi phút**. Đó chính là nhịp tim.

Kỹ thuật này gọi là **rPPG** (*remote photoplethysmography* – đo thể tích máu từ xa bằng hình ảnh).

```
Tim đập → lượng máu dưới da đổi → màu da đổi rất nhẹ → camera ghi lại → tính ra nhịp tim
```

---

## 2. Đọc bộ phận nào trên khuôn mặt?

App đọc **3 mảng da nhỏ**:

```
        ┌───────────┐
        │  ① TRÁN   │      ← mảng nằm trên hai mắt
        └───────────┘
      👁            👁
   ┌──────┐      ┌──────┐
   │② MÁ  │      │③ MÁ  │   ← hai mảng nằm dưới hai mắt
   │ TRÁI │      │ PHẢI │
   └──────┘      └──────┘
```

| Vùng | Vị trí | Tại sao chọn |
|---|---|---|
| ① Trán | Giữa hai mắt, hơi cao lên phía trên | Da phẳng, nhiều mạch máu nhỏ |
| ② Má trái | Dưới mắt trái, lệch ra ngoài một chút | Da mịn, mạch máu nông |
| ③ Má phải | Dưới mắt phải, lệch ra ngoài một chút | Giống má trái |

**Vì sao không đọc cả khuôn mặt?** Vì cả mặt có tóc, lông mày, kính, môi, mắt... Những thứ này thay đổi màu mạnh hơn nhiều so với nhịp tim, nên khi bạn hơi cử động đầu thì chúng "át" mất tín hiệu mạch. Ba mảng da này sạch hơn.

**Làm sao app biết trán và má nằm ở đâu?** Nó dùng **Google ML Kit** (trí tuệ nhân tạo chạy ngay trên điện thoại) để tìm **hai con mắt**. Sau đó app tính ba mảng da dựa vào khoảng cách giữa hai mắt. Nhờ vậy mảng da luôn bám theo mặt, dù mặt bạn gần hay xa camera.

---

## 3. Các bước đo, từ lúc bấm nút đến khi ra kết quả

### Trên điện thoại (Flutter)

| Bước | Việc gì xảy ra |
|---|---|
| 1 | Mở **camera trước**, bạn nhìn thấy mặt mình trong khung |
| 2 | AI tìm hai mắt → xác định 3 mảng da |
| 3 | Với **mỗi khung hình** (khoảng 30 khung/giây), app tính **màu trung bình** (đỏ R, xanh lá G, xanh dương B) của từng mảng da |
| 4 | Bỏ **2 giây đầu** vì camera còn đang tự chỉnh sáng, sẽ làm màu nhấp nháy giả |
| 5 | Ghi liên tục trong **30 giây** |
| 6 | Gửi dãy số màu này lên máy chủ |

> 🔒 **App không gửi video hay ảnh mặt**, chỉ gửi những con số màu trung bình. Vừa riêng tư hơn, vừa tránh việc nén video làm mất tín hiệu mạch vốn rất nhỏ.

### Trên máy chủ (FastAPI, viết bằng Python)

| Bước | Việc gì xảy ra | Ví dụ dễ hiểu |
|---|---|---|
| 1 | **Làm đều dữ liệu**: camera đôi khi bỏ lỡ khung hình, nên server sắp lại các điểm cho cách đều nhau | Như xếp lại các cột mốc trên đường cho đều khoảng cách |
| 2 | **Tách mạch khỏi ánh sáng**: dùng 2 phương pháp **POS** và **CHROM** để loại bỏ phần thay đổi do ánh sáng phòng, chỉ giữ phần thay đổi do máu | Như lọc tiếng nhạc ra khỏi tiếng ồn |
| 3 | **Đếm nhịp**: dùng phép biến đổi **Fourier (FFT)** xem màu da "đập" với tần số nào mạnh nhất | Như nghe một hợp âm rồi tìm xem nốt nào to nhất |
| 4 | **Đổi ra nhịp/phút**: tần số (lần/giây) × 60 = nhịp tim | 1,2 lần/giây × 60 = **72 nhịp/phút** |
| 5 | **Bỏ phiếu**: có 3 vùng × 2 phương pháp = **6 kết quả**. Server lấy nhóm các kết quả giống nhau nhất | Như hỏi 6 bạn, ai cũng nói "72" thì tin 72 |
| 6 | Trả kết quả về điện thoại | |

---

## 4. Giải thích các từ khó

**Tần số và nhịp tim.** Tần số là số lần lặp lại trong 1 giây (đơn vị Hz). Nhịp tim là số lần đập trong 1 **phút**. Đổi qua lại: `nhịp/phút = Hz × 60`.
App chỉ tìm trong khoảng **0,75 – 3 Hz**, tức **45 – 180 nhịp/phút**, là khoảng nhịp tim bình thường của người.

**FFT (biến đổi Fourier).** Công cụ toán học tách một tín hiệu lộn xộn thành nhiều "sóng đều" có tần số khác nhau, và cho biết sóng nào mạnh nhất. Với màu da, sóng mạnh nhất thường là nhịp tim.

**POS và CHROM.** Hai công thức do các nhà khoa học công bố (Wang 2017, de Haan 2013). Cả hai đều dùng **sự chênh lệch giữa ba màu R, G, B** để loại bỏ thay đổi do ánh sáng (ánh sáng đổi thì cả ba màu cùng đổi, còn máu thì làm màu xanh lá đổi nhiều hơn). Dùng cả hai để kiểm tra chéo cho nhau.

**SNR (tỉ số tín hiệu trên nhiễu).** Đo xem tín hiệu nhịp tim "to" hơn nhiễu bao nhiêu. Số càng cao thì kết quả càng đáng tin.

**Bỏ phiếu (agreement).** App hiện kiểu "4/6" nghĩa là 4 trong 6 kết quả cùng ra một nhịp (lệch nhau không quá 5 nhịp). Càng nhiều phiếu giống nhau thì càng đáng tin.

---

## 5. Vì sao phải đo tới 30 giây?

Đo càng lâu thì càng chính xác. Đo 13 giây chỉ phân biệt được các nhịp cách nhau khoảng 4–5 nhịp/phút, và một cái chớp mắt hay nuốt nước bọt cũng làm lệch kết quả. Đo 30 giây thì phân biệt được tới khoảng **2 nhịp/phút**, và mạch đủ nổi bật so với các nhiễu nhỏ.

---

## 6. Những gì làm kết quả bị sai

| Nguyên nhân | Cách app xử lý |
|---|---|
| Phòng tối hoặc ánh sáng nhấp nháy | Nên đo ở nơi đủ sáng, ánh sáng ổn định |
| Bạn cử động hoặc quay đầu | Mảng da bám theo mắt; nếu mất mặt quá 2 giây thì **đo lại từ đầu** |
| Camera tự đổi độ sáng | **Khóa lấy nét và độ sáng** sau 2 giây đầu |
| Tóc hoặc kính che | Chỉ chọn 3 mảng da, tránh tóc và kính |
| Điện thoại quay chậm (dưới 8 khung/giây) | Server từ chối, không tính |

**Lưu ý quan trọng:** ứng dụng này chỉ để **tham khảo**, không phải thiết bị y tế. Trong thử nghiệm của nhóm, kết quả đã được so với đồng hồ đeo tay nhưng mới trên **vài lần đo**, nên chưa thể khẳng định độ chính xác chung.

---

## 7. Tóm tắt công nghệ dùng (ngắn gọn)

| Phần | Công nghệ | Làm gì |
|---|---|---|
| Ứng dụng điện thoại | **Flutter** (ngôn ngữ Dart) | Giao diện, chạy được cả Android và iPhone |
| Camera | gói `camera` | Lấy từng khung hình từ camera trước |
| Tìm mắt | **Google ML Kit** | AI nhận diện mặt và vị trí mắt, chạy ngay trên điện thoại |
| Gọi máy chủ | gói `dio` | Gửi dữ liệu qua Internet |
| Vẽ biểu đồ | `fl_chart` | Biểu đồ nhịp tim, cân nặng, calo |
| Quản lý trạng thái | `flutter_bloc` | Quản lý đăng nhập |
| Lưu đăng nhập an toàn | `flutter_secure_storage` | Cất "chìa khóa" đăng nhập (token) trong vùng bảo mật của máy |
| Máy chủ | **FastAPI** (Python) | Nhận dữ liệu, tính nhịp tim, lưu kết quả |
| Tính toán | NumPy, SciPy, rPPG-Toolbox | Lọc tín hiệu, FFT, POS, CHROM |
| Cơ sở dữ liệu | **SQLite** | Lưu người dùng và các lần đo |
| Bảo mật | JWT, bcrypt | Đăng nhập an toàn, mật khẩu được băm không lưu nguyên văn |
| Chạy trên mạng | Docker, Fly.io, Cloudflare | Đưa máy chủ lên Internet |

---

## 8. Sơ đồ tổng thể một lần đo

```
 📱 ĐIỆN THOẠI                                 ☁️ MÁY CHỦ
┌──────────────────────────┐                ┌──────────────────────────────┐
│ Camera trước quay mặt    │                │ Làm đều các điểm dữ liệu     │
│          ↓               │                │          ↓                   │
│ AI tìm 2 mắt             │                │ POS + CHROM tách nhịp mạch   │
│          ↓               │   30 giây      │   khỏi ánh sáng              │
│ Cắt 3 mảng da: trán,     │  số liệu màu   │          ↓                   │
│ má trái, má phải         │ ─────────────► │ FFT tìm tần số mạnh nhất     │
│          ↓               │                │          ↓                   │
│ Tính màu trung bình      │                │ ×60 = nhịp/phút (6 kết quả)  │
│ R, G, B mỗi khung hình   │                │          ↓                   │
│                          │  ◄──────────── │ Bỏ phiếu → chọn nhịp tim     │
│ Hiện nhịp tim cho bạn    │    kết quả     │ Lưu vào cơ sở dữ liệu        │
└──────────────────────────┘                └──────────────────────────────┘
```

---

## 9. Câu hỏi thường gặp

**Camera chụp mặt có bị lưu ảnh không?**
Không. App chỉ lấy con số màu trung bình, không gửi hay lưu ảnh/video mặt.

**Tại sao máy chủ phải tính, không tính ngay trên điện thoại?**
Vì thuật toán dùng thư viện Python khoa học có sẵn, đã được cộng đồng nghiên cứu kiểm chứng. Tính trên server giúp dùng lại thuật toán chuẩn mà không phải tự viết lại.

**Thiếu mạng thì sao?**
Không đo được, vì cần gửi dữ liệu lên máy chủ. Đây là một hạn chế của ứng dụng.

**Có chính xác như đồng hồ thông minh không?**
Chưa thể khẳng định. Nhóm mới so sánh trên vài lần đo, nên kết quả chỉ mang tính tham khảo.
