# DIY Cắt Sắt v2.1 — plugin SketchUp 2023

| File | Dùng để |
|---|---|
| `diy_cat_sat.rb` | Plugin (menu **Extensions › DIY Cắt Sắt v2.1**, 4 công cụ) |
| `test.rb` | Test tự động chạy trong SketchUp, ghi `C:\diy_test\log.txt`; đạt hết thì tự chép plugin vào `%AppData%\SketchUp\SketchUp 2023\SketchUp\Plugins` |
| `run_test.bat` | Chép 2 file trên vào `C:\diy_test`, mở SketchUp với `-RubyStartup`, in log |
| `dev_tests/core_test.rb` | Test phần tính toán, chạy bằng Ruby thường: `ruby dev_tests/core_test.rb` |
| `dev_tests/mock_sketchup.rb` | Chạy thử `test.rb` trên API SketchUp giả lập (chỉ bắt lỗi code, không đo hình thật) |

## Chạy test trên Windows
Bấm đúp `run_test.bat`, hoặc chạy:

    "C:\Program Files\SketchUp\SketchUp 2023\SketchUp.exe" -RubyStartup C:\diy_test\test.rb

Nếu SketchUp hiện màn hình Welcome, chọn mẫu (mm) — test chạy sau 2 giây. Nếu khi tự đóng
SketchUp hỏi lưu file, chọn **No**.

## Quy ước tính
- Mặt trải phẳng: y = 0 là lưng (mặt ngoài khung), đỉnh khía V ở y = lưng, miệng khía ở y = W.
- Lưng mặc định = độ dày thành ống t. Sâu khía = W − lưng. Nửa rộng miệng khía = (W − lưng)·tan(góc/2)
  (góc 90° ⇒ cạnh vát 45°).
- Khung vát 1 thanh: dài khai triển = 2·(A − 2·lưng) + 2·(B − 2·lưng), 3 khía 90° + 2 nửa khía ở mối nối.
- Khung bo góc kiểu A (1 thanh, mối nối giữa cạnh dưới): dài = 2(A−2R) + 2(B−2R) + 2π(R − lưng),
  mỗi góc n khía (mặc định 6 × 15°).
- R tối thiểu để các khía không chồng nhau và bán kính trong ≥ 2 mm (25x25x1.2, 6 khía ⇒ 27.5 mm);
  R tối đa = nửa cạnh ngắn. Ngoài khoảng này plugin tự đổi R và báo.
- Công cụ 4: khung vát mặc định cắt 4 thanh rời (dài ngoài A, B); khung bo góc luôn dùng chiều dài
  khai triển. Tối ưu First-Fit/Best-Fit Decreasing, có mạch cắt và bỏ đầu cây.
