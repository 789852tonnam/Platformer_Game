# Platformer Game

โปรเจกต์ Verilog สำหรับแสดงฉากแบบ tile และเลื่อนฉากแนวนอนบน VGA Playground ใช้ภาพจาก SunnyLand และแผนที่ที่ประกอบจาก tile ขนาด 16×16 พิกเซล

**[เปิดโปรเจกต์ใน VGA Playground](https://vga-playground.com/?repo=https://github.com/789852tonnam/Platformer_Game)**

## การใช้งาน

1. เปิดลิงก์ VGA Playground ด้านบน และรอโหลดโปรเจกต์
2. เปิดตัวควบคุม gamepad แล้วกด **ซ้าย / ขวา** เพื่อเลื่อนดูแผนที่

แสดงผลที่ 640×480 พิกเซล ใช้สี RGB222 รวม 64 สี พร้อม dithering ที่แปลงไว้ล่วงหน้าใน Python ภาพขยาย 2 เท่า ทำให้แต่ละ tile มีขนาด 32×32 พิกเซลบนจอ

แผนที่มีขนาด **60×15 tiles** ยาว 3 หน้าจอ มีพื้นหญ้า หลุม พื้นลอยด้านนอก และถ้ำ โดย `scroll_offset` อยู่ในช่วง 0–640 พิกเซลต้นฉบับ และเปลี่ยนครั้งละ 1 ต่อเฟรมเมื่อกดปุ่ม

## หลักการทำงาน

```text
พิกัด VGA → หาร 2 และบวก scroll_offset → Map ROM → tile ID → Tile ROM
                                                                   ↓
Back ROM → สีฉากหลัง ───────────────────────────────→ เลือกสี → VGA
```

- **Map ROM:** เก็บ tile ID จำนวน 900 ช่อง แต่ละช่องมีขนาด 10 บิต
- **Tile ROM:** เก็บภาพทีละ tile จำนวน 575 tiles ตามลำดับในแผ่น 25×23 ช่อง
- **Back ROM:** เก็บฉากหลังขนาด 384×240 พิกเซล
- ข้อมูลสีแต่ละพิกเซลมี 7 บิต `{opaque, R[1:0], G[1:0], B[1:0]}` ถ้า `opaque = 0` จะแสดงสีฉากหลัง

## โครงสร้างไฟล์

```text
Platformer_Game/
├── info.yaml                 # ข้อมูลโปรเจกต์และรายชื่อ source สำหรับ Playground
├── README.md
├── .gitignore                # ไม่ติดตามไฟล์ PDF และ Python cache
├── src/
│   ├── bg_scrolling.v        # Top module, อ่าน ROM, รวมภาพ และเลื่อนฉาก
│   ├── hsync_generator.v     # สร้างพิกัดและสัญญาณ VGA sync
│   └── gamepad_pmod.v        # อ่านปุ่ม gamepad
├── used_art/
│   ├── back.png              # ภาพฉากหลังต้นฉบับ
│   ├── tileset.png           # แผ่น tile ต้นฉบับ
│   ├── back.mem              # ข้อมูล Back ROM
│   ├── tileset.mem           # ข้อมูล Tile ROM เรียงทีละ tile 16×16
│   ├── map.mem               # แผนที่ 60×15 เรียงตามแถว
│   ├── back_rgb222.png       # ภาพหลังแปลงสี
│   ├── tileset_rgb222.png
│   ├── map.png               # ภาพแผนที่ด้วยสีต้นฉบับ
│   ├── map_rgb222.png        # ภาพแผนที่ด้วยสี RGB222
│   ├── convert_assets.py     # แปลง PNG เป็น ROM พร้อม Bayer dithering
│   ├── build_map.py          # กำหนด tile ในแผนที่และสร้าง map.mem
│   └── README.txt            # รูปแบบข้อมูล ROM และรายละเอียดแผนที่
└── art_asset/                # ชุด asset ต้นฉบับที่ดาวน์โหลดมา
```

## สร้างไฟล์ ROM ใหม่

ใช้ Python และ Pillow รันจากโฟลเดอร์หลักของโปรเจกต์:

```bash
python3 -m pip install Pillow
python3 used_art/convert_assets.py
python3 used_art/build_map.py
```

หากรัน Verilog simulator ในเครื่อง ให้ใช้ `src/` เป็น working directory เพื่อให้ path `../used_art/*.mem` ตรงกับ `$readmemh` ในโค้ด

## Asset

ภาพจาก **[SunnyLand โดย Ansimuz](https://ansimuz.itch.io/sunny-land-pixel-game-art)** ซึ่งระบุสัญญาอนุญาต CC0 บนหน้า asset
