# AI Accelerator RTL & Functional Verification

Repository phục vụ thiết kế phần cứng (RTL) và kiểm tra chức năng (Functional Verification) cho đề tài Bộ gia tốc AI (AI Accelerator).

---

## 📁 Cấu trúc thư mục (Directory Structure)

```text
AI-Accelerator-RTL/
├── docs/                 # Tài liệu thiết kế, sơ đồ khối (Block Diagram), specs
├── model/                # Mô hình thuật toán tham chiếu (Golden Model)
│   ├── test_vectors/     # Dữ liệu kiểm thử đầu vào & đầu ra mẫu (Hex, text, bin)
│   └── weights/          # Trọng số fixed-point của từng lớp (quantized weights)
├── rtl/                  # Mã nguồn phần cứng (Verilog / SystemVerilog)
├── tb/                   # Testbench, stimulus generators, scoreboards
├── sim/                  # Môi trường mô phỏng
│   └── Makefile          # Makefile biên dịch & chạy mô phỏng
├── .gitignore            # Bỏ qua các file rác sinh ra trong quá trình sim
├── Makefile              # Makefile ở thư mục gốc (forward lệnh sang sim/)
└── README.md
```

---

## 🛠 Yêu cầu môi trường (Prerequisites)

Dự án sử dụng bộ công cụ nguồn mở:
- **Icarus Verilog (`iverilog`)**: Trình biên dịch và mô phỏng Verilog.
- **GTKWave (`gtkwave`)**: Trình hiển thị dạng sóng (Waveform viewer).
- **Make**: Trình thực thi Makefile.

### Cài đặt trên Linux / WSL (Ubuntu/Debian):
```bash
sudo apt update
sudo apt install iverilog gtkwave make
```

---

## 🚀 Hướng dẫn mô phỏng (How to Run Simulation)

Bạn có thể chạy lệnh `make` trực tiếp ở thư mục gốc hoặc trong thư mục `sim/`:

| Lệnh | Ý nghĩa |
| :--- | :--- |
| `make` hoặc `make sim` | Biên dịch toàn bộ RTL, TB và chạy mô phỏng |
| `make compile` | Chỉ biên dịch cú pháp bằng `iverilog` |
| `make wave` | Mở dạng sóng `.vcd` bằng GTKWave |
| `make clean` | Xóa thư mục build và các file tạm sinh ra khi mô phỏng |
| `make TB=<tên_tb>` | Chỉ định testbench cụ thể để chạy (ví dụ: `make TB=tb_mac`) |

---

## 📝 Quy ước làm việc nhóm (Team Collaboration)

1. **Pull code mới nhất trước khi làm việc:**
   ```bash
   git pull origin main
   ```
2. **Tạo branch riêng cho từng tính năng:**
   ```bash
   git checkout -b feature/<ten-tinh-nang>
   ```
3. **Commit rõ ràng & tạo Pull Request (PR) để review trước khi merge vào `main`.**
