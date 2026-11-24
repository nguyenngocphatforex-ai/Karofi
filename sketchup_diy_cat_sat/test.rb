# encoding: UTF-8
# =============================================================================
#  test.rb — kiểm thử tự động DIY Cắt Sắt v2.1 trong SketchUp 2023
#
#  Chạy:
#    "C:\Program Files\SketchUp\SketchUp 2023\SketchUp.exe" -RubyStartup C:\diy_test\test.rb
#
#  - Nạp C:\diy_test\diy_cat_sat.rb (cùng thư mục với test.rb)
#  - Dựng khung 400x400 sắt 25x25x1.2: vát 45° và bo góc R50
#  - Chạy 4 công cụ, đo kích thước, ghi C:\diy_test\log.txt
#  - Nếu TẤT CẢ đạt: chép plugin vào %AppData%\SketchUp\SketchUp 2023\SketchUp\Plugins
#  - Đặt biến môi trường DIY_AUTOQUIT=1 để tự đóng SketchUp sau khi chạy xong.
# =============================================================================
require 'fileutils'

module DIYTest
  DIR      = File.dirname(File.expand_path(__FILE__))
  LOG      = File.join(DIR, 'log.txt')
  PLUGIN   = File.join(DIR, 'diy_cat_sat.rb')
  LIB_JSON = File.join(DIR, 'test_quy_cach.json')
  IN3_TO_MM3 = 16_387.064
  IN2_TO_MM2 = 645.16

  @pass = 0
  @fail = 0
  @errors = 0

  class << self
    attr_reader :pass, :fail, :errors

    def log(msg)
      line = "#{Time.now.strftime('%H:%M:%S')} #{msg}"
      File.open(LOG, 'a:UTF-8') { |f| f.puts(line) }
      puts line
    end

    def check(name, ok, detail = '')
      if ok
        @pass += 1
        log("  [ĐẠT ]  #{name}  #{detail}")
      else
        @fail += 1
        log("  [LỖI ]  #{name}  #{detail}")
      end
      ok
    end

    def near(name, measured, expected, tol)
      ok = measured.is_a?(Numeric) && (measured - expected).abs <= tol
      check(name, ok, "đo=#{f(measured)}  cần=#{f(expected)}  (±#{f(tol)})")
    end

    def f(v)
      v.is_a?(Numeric) ? format('%.3f', v) : v.inspect
    end

    # Chạy một khối; ngoại lệ được ghi log và tính là lỗi, các bước sau vẫn chạy.
    def step(title)
      log("--- #{title}")
      yield
    rescue Exception => e # rubocop:disable Lint/RescueException
      @errors += 1
      log("  [NGOẠI LỆ] #{e.class}: #{e.message}")
      e.backtrace.to_a.first(10).each { |l| log("      #{l}") }
      nil
    end

    def core
      DIYCatSat::Core
    end

    def dims(bb)
      [bb.width.to_mm, bb.height.to_mm, bb.depth.to_mm]
    end

    def faces(group)
      group.entities.grep(Sketchup::Face)
    end

    # ---------------------------------------------------------------- DXF đọc
    def read_dxf(path)
      raw = File.read(path, mode: 'rb').split(/\r?\n/)
      pairs = raw.each_slice(2).map { |c, v| [c.to_s.strip, v.to_s.strip] }
      ents = []
      cur = nil
      pairs.each do |code, val|
        if code == '0'
          ents << cur if cur
          cur = { type: val }
        elsif cur
          cur[code] = val
        end
      end
      ents << cur if cur
      ents
    end

    def dxf_lines(ents, layer = nil)
      ents.select { |e| e[:type] == 'LINE' && (layer.nil? || e['8'] == layer) }.map do |e|
        [e['10'].to_f, e['20'].to_f, e['11'].to_f, e['21'].to_f]
      end
    end

    # Kiểm tra cạnh khía trong 1 dải (pattern) của DXF: đỉnh ở y = y0 + back,
    # miệng ở y = y0 + w, và độ nghiêng đúng tan(góc/2).
    def check_dxf_band(label, lines, y0, w, back, angles_deg)
      band = lines.select { |l| [l[1], l[3]].min > y0 - 0.01 && [l[1], l[3]].max < y0 + w + 0.01 }
      apex_y = band.map { |l| [l[1], l[3]].min }.min
      near("#{label}: đỉnh khía ở độ dày lưng", apex_y.to_f - y0, back, 0.001)
      mouth = band.map { |l| [l[1], l[3]].max }.max
      near("#{label}: miệng khía ở mặt trong", mouth.to_f - y0, w, 0.001)
      d = w - back
      expected = angles_deg.map { |a| (d * Math.tan(a * Math::PI / 360.0)).round(3) }.uniq.sort
      got = band.map { |l| (l[0] - l[2]).abs.round(3) }.uniq.sort
      check("#{label}: cạnh vát đúng (nửa rộng = (W-lưng)·tan(góc/2))",
            !got.empty? && got.all? { |g| expected.any? { |e| (g - e).abs < 0.002 } },
            "đo=#{got.inspect} cần=#{expected.inspect}")
      check("#{label}: không còn hard-code 1.2", (back - 1.2).abs < 1e-9 || (apex_y.to_f - y0 - 1.2).abs > 0.01,
            "lưng=#{back}")
    end

    # ================================================================== chạy
    def run
      File.delete(LOG) if File.exist?(LOG)
      log("=== DIY Cắt Sắt — kiểm thử tự động — SketchUp #{Sketchup.version} — Ruby #{RUBY_VERSION}")
      log("Plugin: #{PLUGIN}")

      step('Nạp plugin') do
        load PLUGIN
        check('Nạp plugin, đúng phiên bản 2.1', DIYCatSat::VERSION.start_with?('2.1'), DIYCatSat::VERSION)
        DIYCatSat.silent = true
        DIYCatSat.clear_warnings
      end
      return finish unless defined?(DIYCatSat::Core)

      model = Sketchup.active_model
      model.start_operation('DIY test', true)
      model.active_entities.clear!
      model.commit_operation

      # Core dùng qua hàm core()
      prof = nil

      # ------------------------------------------------ (1) thư viện
      step('(1) Thư viện quy cách JSON') do
        File.delete(LIB_JSON) if File.exist?(LIB_JSON)
        lib = DIYCatSat.library(LIB_JSON)
        check('Tạo file JSON mặc định', File.exist?(LIB_JSON), LIB_JSON)
        lib.add(25, 25, 1.2)
        lib.add(25, 25, 1.4, 'thu_1.4')
        lib2 = DIYCatSat::Library.new(LIB_JSON)
        prof = lib2.find('25x25x1.2')
        check('Đọc lại 25x25x1.2 từ JSON', prof && prof['w'] == 25.0 && prof['t'] == 1.2, prof.inspect)
        check('Đọc lại quy cách tự đặt tên', lib2.find('thu_1.4') && lib2.find('thu_1.4')['t'] == 1.4)
        check('Xoá quy cách', lib2.remove('thu_1.4') && DIYCatSat::Library.new(LIB_JSON).find('thu_1.4').nil?)
        bad = begin
          lib2.add(25, 25, 13)
          false
        rescue ArgumentError
          true
        end
        check('Từ chối quy cách sai (t quá dày)', bad)
        DIYCatSat.library(LIB_JSON)
      end

      miter = nil
      round = nil
      # ------------------------------------------------ (2a) khung vát 45°
      step('(2a) Khung vát 45° 400x400, sắt 25x25x1.2') do
        miter = DIYCatSat::Build.miter_frame(400, 400, '25x25x1.2', origin: [0, 0, 0])
        w, h, d = dims(miter.bounds)
        log("  Kích thước khung: #{f(w)} x #{f(h)} x #{f(d)} mm")
        near('Khung vát: rộng', w, 400.0, 0.01)
        near('Khung vát: cao', h, 400.0, 0.01)
        near('Khung vát: dày', d, 25.0, 0.01)
        bars = miter.entities.grep(Sketchup::Group)
        check('Khung vát: 4 thanh', bars.size == 4, "có #{bars.size}")
        check('Không dùng intersect_with (mỗi thanh 6 mặt)', bars.all? { |g| faces(g).size == 6 },
              bars.map { |g| faces(g).size }.inspect)
        exp_vol = (400.0 + 350.0) / 2.0 * 25.0 * 25.0
        bars.each do |g|
          bw, bh, = dims(g.bounds)
          log("  #{g.name}: #{f(bw)} x #{f(bh)} mm")
          check("#{g.name}: khối đặc kín (manifold)", g.manifold?)
          near("#{g.name}: thể tích (mm³)", g.volume * IN3_TO_MM3, exp_vol, exp_vol * 0.001)
          lens = g.entities.grep(Sketchup::Edge).map { |e| e.length.to_mm.round(3) }
          check("#{g.name}: cạnh ngoài 400, cạnh trong 350, cạnh vát 35.355",
                lens.include?(400.0) && lens.include?(350.0) && lens.count { |l| (l - 35.355).abs < 0.002 } >= 2,
                lens.uniq.sort.inspect)
        end
      end

      # ------------------------------------------------ (2b) khung bo góc R50
      step('(2b) Khung bo góc kiểu A R50 400x400, sắt 25x25x1.2') do
        DIYCatSat.clear_warnings
        round = DIYCatSat::Build.rounded_frame(400, 400, '25x25x1.2', 50, origin: [600, 0, 0])
        w, h, d = dims(round.bounds)
        log("  Kích thước khung: #{f(w)} x #{f(h)} x #{f(d)} mm")
        near('Khung bo: rộng', w, 400.0, 0.01)
        near('Khung bo: cao', h, 400.0, 0.01)
        near('Khung bo: dày', d, 25.0, 0.01)
        inf = DIYCatSat::Build.info(round)
        near('Khung bo: R giữ nguyên 50', inf['r'].to_f, 50.0, 1e-9)
        check('Khung bo: không cảnh báo đổi R khi R hợp lệ', DIYCatSat.warnings.empty?, DIYCatSat.warnings.inspect)
        check('Khung bo: có hình (followme thành công)', faces(round).size > 10, "#{faces(round).size} mặt")
        check('Khung bo: khối kín (manifold)', round.manifold?)
        # Cạnh đường dẫn vẫn còn: đếm cạnh ở z=0 nằm trên đường bao ngoài
        on_path = round.entities.grep(Sketchup::Edge).count do |e|
          [e.start.position, e.end.position].all? do |p|
            p.z.abs < 1e-4 && core.dist_to_rounded_rect(p.x.to_mm, p.y.to_mm, 400, 400, 50) < 0.01
          end
        end
        segs = inf['path_segments'].to_i
        check('Khung bo: cạnh đường dẫn followme còn nguyên', on_path >= segs && segs > 0,
              "cạnh trên đường dẫn=#{on_path}, số đoạn đường dẫn=#{segs}")
        t = 1.2
        area = 25.0 * 25.0 - (25.0 - 2 * t)**2
        rc = 50.0 - 12.5
        exp_vol = area * (4 * (400.0 - 100.0) + 2 * Math::PI * rc)
        vol = round.volume * IN3_TO_MM3
        near('Khung bo: thể tích ống rỗng (mm³, ±1.5%)', vol, exp_vol, exp_vol * 0.015)
      end

      step('(2c) Tự đổi R và có thông báo') do
        DIYCatSat.clear_warnings
        small = DIYCatSat::Build.rounded_frame(400, 400, '25x25x1.2', 10, origin: [1200, 0, 0])
        r = DIYCatSat::Build.info(small)['r'].to_f
        check('R=10 được tự tăng', r > 25.0, "R mới = #{f(r)}")
        check('Có thông báo đổi R', DIYCatSat.warnings.any? { |m| m.include?('R') && m.include?(core.fmt(r)) },
              DIYCatSat.warnings.inspect)
        w, h, = dims(small.bounds)
        near('Khung R tự đổi: rộng', w, 400.0, 0.01)
        near('Khung R tự đổi: cao', h, 400.0, 0.01)
        check('Khung R tự đổi: manifold', small.manifold?)
        res = core.resolve_radius(400, 400, 25, 1.2, 500)
        check('R=500 bị giới hạn về 200 và có thông báo', res[:r] == 200.0 && res[:changed], res[:messages].inspect)
      end

      # ------------------------------------------------ (3) trải phẳng
      step('(3) Trải phẳng khía V — khung vát 45°') do
        raise 'chưa có khung vát' unless miter
        out = DIYCatSat::Build.unfold(miter)
        pat = out[:pattern]
        g = out[:group]
        near('Lưng mặc định = độ dày thành ống', pat[:back], 1.2, 1e-9)
        exp_l = 4 * (400.0 - 2 * 1.2)
        w, h, = dims(g.bounds)
        log("  Trải phẳng vát: #{f(w)} x #{f(h)} mm, #{pat[:notches].size} khía")
        near('Trải phẳng vát: dài khai triển', w, exp_l, 0.01)
        near('Trải phẳng vát: rộng = W', h, 25.0, 0.01)
        check('Trải phẳng vát: 3 khía 90° + 2 nửa khía đầu thanh',
              pat[:notches].size == 3 && pat[:notches].all? { |n| n[:angle] == 90.0 } && pat[:end_left] == 90.0)
        d = 25.0 - 1.2
        near('Trải phẳng vát: diện tích mặt (mm²)', faces(g).sum(&:area) * IN2_TO_MM2,
             exp_l * 25.0 - 4 * d * d, 0.5)
      end

      step('(3) Trải phẳng khía V — khung bo góc R50') do
        raise 'chưa có khung bo' unless round
        out = DIYCatSat::Build.unfold(round)
        pat = out[:pattern]
        g = out[:group]
        exp_l = 4 * 300.0 + 2 * Math::PI * (50.0 - 1.2)
        w, h, = dims(g.bounds)
        log("  Trải phẳng bo: #{f(w)} x #{f(h)} mm, #{pat[:notches].size} khía")
        near('Trải phẳng bo: dài khai triển', w, exp_l, 0.01)
        near('Trải phẳng bo: rộng = W', h, 25.0, 0.01)
        n = pat[:n]
        check('Trải phẳng bo: 4 góc x n khía, tổng góc 360°',
              pat[:notches].size == 4 * n && (pat[:notches].sum { |x| x[:angle] } - 360.0).abs < 1e-6,
              "n=#{n}")
        hw = (25.0 - 1.2) * Math.tan(90.0 / n * Math::PI / 360.0)
        near('Trải phẳng bo: diện tích mặt (mm²)', faces(g).sum(&:area) * IN2_TO_MM2,
             exp_l * 25.0 - 4 * n * (25.0 - 1.2) * hw, 0.5)
      end

      step('(3) Độ dày lưng nhập vào & mặc định theo t') do
        p2 = core.pattern_for(DIYCatSat::Build.info(miter), back: 2.0)
        near('Lưng nhập 2.0 → dài khai triển', p2[:length], 4 * (400.0 - 4.0), 1e-9)
        info14 = DIYCatSat::Build.info(miter).merge('t' => 1.4, 'back' => nil)
        near('Sắt t=1.4 không nhập lưng → lưng = 1.4', core.pattern_for(info14)[:back], 1.4, 1e-9)
      end

      # ------------------------------------------------ (4) tối ưu cắt + DXF
      step('(4) Tối ưu cắt cây 6m') do
        p1 = DIYCatSat.cut_plan([miter], stock: 6000, kerf: 2)
        log("  Vát 45°:\n" + core.plan_report(p1).gsub(/^/, '      '))
        check('Vát: 4 đoạn 400 trong 1 cây', p1[:bar_count] == 1 && p1[:piece_count] == 4 &&
                                               p1[:bars][0][:pieces].all? { |x| x[:length] == 400.0 })
        p2 = DIYCatSat.cut_plan([round], stock: 6000, kerf: 2)
        log("  Bo góc:\n" + core.plan_report(p2).gsub(/^/, '      '))
        exp_l = 4 * 300.0 + 2 * Math::PI * 48.8
        near('Bo góc: tự dùng chiều dài khai triển (không báo lỗi)', p2[:bars][0][:pieces][0][:length], exp_l, 1e-6)
        p3 = DIYCatSat.cut_plan([round], stock: 6000, kerf: 2, qty: 10)
        check('Bo góc x10: cần 4 cây (3+3+3+1)', p3[:bar_count] == 4,
              p3[:bars].map { |b| b[:pieces].size }.inspect)
        p4 = DIYCatSat.cut_plan([miter, round], stock: 6000, kerf: 2, qty: 3)
        log("  Hỗn hợp x3:\n" + core.plan_report(p4).gsub(/^/, '      '))
        check('Hỗn hợp: mọi cây không vượt 6000', p4[:bars].all? { |b| b[:used] + b[:kerf_loss] <= 6000.0 + 1e-6 })
        @plan = p4
      end

      step('(4) Xuất DXF') do
        dxf1 = File.join(DIR, 'test_lung_mac_dinh.dxf')
        dxf2 = File.join(DIR, 'test_lung_2.0.dxf')
        DIYCatSat.export_dxf(dxf1, [miter, round], plan: @plan)
        DIYCatSat.export_dxf(dxf2, [miter, round], back: 2.0)
        [[dxf1, 1.2], [dxf2, 2.0]].each do |path, back|
          ents = read_dxf(path)
          check("DXF #{File.basename(path)}: có ENTITIES và EOF", ents.any? { |e| e[:type] == 'EOF' } &&
                                                                  ents.count { |e| e[:type] == 'LINE' } > 20)
          lines = dxf_lines(ents, 'KHIA')
          check_dxf_band("DXF lưng #{back} khung vát", lines, 0.0, 25.0, back, [90.0])
          n = DIYCatSat::Build.info(round)['n'].to_i
          check_dxf_band("DXF lưng #{back} khung bo", lines, -(25.0 + 60.0), 25.0, back, [90.0 / n])
          texts = ents.select { |e| e[:type] == 'TEXT' }.map { |e| e['1'] }
          check("DXF #{File.basename(path)}: ghi LUNG=#{core.fmt(back)}",
                texts.count { |s| s.include?("LUNG=#{core.fmt(back)} ") } == 2, texts.first(2).inspect)
          all = dxf_lines(ents)
          maxx = all.select { |l| [l[1], l[3]].min > -0.01 && [l[1], l[3]].max < 25.01 }.map { |l| [l[0], l[2]].max }.max
          near("DXF lưng #{back}: dài khung vát", maxx.to_f, 4 * (400.0 - 2 * back), 0.001)
        end
      end

      finish
    end

    def finish
      ok = @fail.zero? && @errors.zero? && @pass > 0
      log("=== KẾT QUẢ: #{@pass} đạt, #{@fail} lỗi, #{@errors} ngoại lệ  →  #{ok ? 'ĐẠT' : 'CHƯA ĐẠT'}")
      if ok
        step('Chép plugin vào thư mục Plugins') do
          dest_dir = File.join(ENV['APPDATA'].to_s, 'SketchUp', 'SketchUp 2023', 'SketchUp', 'Plugins')
          FileUtils.mkdir_p(dest_dir)
          dest = File.join(dest_dir, 'diy_cat_sat.rb')
          FileUtils.cp(PLUGIN, dest)
          check('Đã chép plugin', File.exist?(dest) && File.size(dest) == File.size(PLUGIN), dest)
        end
      else
        log('Không chép plugin vì còn lỗi.')
      end
      if ENV['DIY_AUTOQUIT'] == '1'
        log('Tự đóng SketchUp (DIY_AUTOQUIT=1).')
        UI.start_timer(1.0, false) do
          m = Sketchup.active_model
          m.close(true) if m.respond_to?(:close) rescue nil
          Sketchup.quit
        end
      end
    end
  end
end

# Đợi SketchUp khởi động xong rồi mới chạy.
UI.start_timer(2.0, false) do
  begin
    DIYTest.run
  rescue Exception => e # rubocop:disable Lint/RescueException
    DIYTest.log("NGOẠI LỆ NGOÀI CÙNG: #{e.class}: #{e.message}\n#{e.backtrace.to_a.first(10).join("\n")}")
  end
end
