# encoding: UTF-8
# =============================================================================
#  DIY Cắt Sắt  v2.1  —  plugin SketchUp 2023 (Ruby 2.7)
#
#  4 công cụ:
#   (1) Thư viện quy cách sắt hộp (lưu JSON)
#   (2) Dựng khung vát 45° và khung bo góc kiểu A
#   (3) Trải phẳng thanh, khía rãnh V
#   (4) Tối ưu cắt cây 6 m + xuất DXF
#
#  Sửa so với v2.0:
#   - Thanh vát 45° dựng bằng khối hình thang đặc (add_face + pushpull),
#     không còn dùng intersect_with.
#   - followme: đường dẫn vẽ trong CÙNG group với tiết diện, và đường dẫn là
#     đường bao ngoài ở mặt đáy, nên sau khi quét nó trùng với cạnh của khối;
#     không xoá cạnh đường dẫn.
#   - DXF dùng đúng độ dày lưng nhập vào (không hard-code 1.2) và đúng cạnh
#     vát (nửa bề rộng khía = (W - lưng) * tan(góc/2)).
#   - Độ dày lưng mặc định = độ dày thành ống (t).
#   - Công cụ 4 tự dùng chiều dài khai triển của khung bo góc.
#   - Báo cho người dùng khi tự đổi bán kính R.
#
#  Đơn vị: mọi tham số của API là mm.
# =============================================================================
require 'json'
require 'fileutils'
begin
  require 'sketchup.rb'
rescue LoadError
  # Chạy ngoài SketchUp (kiểm thử phần Core bằng Ruby thường).
end

module DIYCatSat
  VERSION = '2.1.0'.freeze unless const_defined?(:VERSION)
  DICT    = 'DIYCatSat'.freeze unless const_defined?(:DICT)

  # ===========================================================================
  #  CORE — tính toán thuần Ruby, không phụ thuộc SketchUp
  # ===========================================================================
  module Core
    DEFAULT_NOTCHES = 6     # số khía mỗi góc bo (mỗi khía 15°)
    NOTCH_GAP       = 0.5   # mm — khe tối thiểu giữa hai miệng khía kề nhau
    MIN_INNER_R     = 2.0   # mm — bán kính trong tối thiểu của góc bo
    EPS             = 1e-6

    module_function

    def fmt(v, digits = 2)
      s = format("%.#{digits}f", v.to_f)
      s = s.sub(/0+\z/, '').sub(/\.\z/, '') if s.include?('.')
      s == '-0' ? '0' : s
    end

    def profile_name(w, h, t)
      "#{fmt(w)}x#{fmt(h)}x#{fmt(t)}"
    end

    # Chuẩn hoá & kiểm tra 1 quy cách. Trả về Hash có khoá chuỗi.
    def normalize_profile(p)
      w = Float(p['w'] || p[:w])
      h = Float(p['h'] || p[:h])
      t = Float(p['t'] || p[:t])
      validate_profile!(w, h, t)
      name = (p['name'] || p[:name]).to_s.strip
      name = profile_name(w, h, t) if name.empty?
      { 'name' => name, 'w' => w, 'h' => h, 't' => t }
    end

    def validate_profile!(w, h, t)
      raise ArgumentError, 'Kích thước W, H phải > 0' unless w > 0 && h > 0
      raise ArgumentError, 'Độ dày thành t phải > 0' unless t > 0
      if 2 * t >= [w, h].min
        raise ArgumentError, "Độ dày t=#{fmt(t)} quá lớn so với #{fmt(w)}x#{fmt(h)}"
      end
      true
    end

    # ---------------------------------------------------------------- khung vát
    # 4 thanh hình thang, mặt phẳng XY, gốc (0,0) ở góc ngoài dưới-trái.
    # w = bề rộng tiết diện nằm trong mặt phẳng khung.
    def miter_bars(a, b, w)
      a = a.to_f; b = b.to_f; w = w.to_f
      unless a > 2 * w && b > 2 * w
        raise ArgumentError, "Khung #{fmt(a)}x#{fmt(b)} quá nhỏ cho sắt rộng #{fmt(w)}"
      end
      [
        { name: 'Duoi',  outer: a, inner: a - 2 * w,
          poly: [[0, 0], [a, 0], [a - w, w], [w, w]] },
        { name: 'Phai',  outer: b, inner: b - 2 * w,
          poly: [[a, 0], [a, b], [a - w, b - w], [a - w, w]] },
        { name: 'Tren',  outer: a, inner: a - 2 * w,
          poly: [[a, b], [0, b], [w, b - w], [a - w, b - w]] },
        { name: 'Trai',  outer: b, inner: b - 2 * w,
          poly: [[0, b], [0, 0], [w, w], [w, b - w]] }
      ]
    end

    # ------------------------------------------------------------ khung bo góc
    def min_radius(w, back, n)
      theta = (Math::PI / 2.0) / n
      d     = w - back
      hw    = d * Math.tan(theta / 2.0)
      rh    = (2.0 * hw + NOTCH_GAP) / theta   # bán kính đường bản lề tối thiểu
      r     = [back + rh, w + MIN_INNER_R].max
      (r * 2.0).ceil / 2.0                      # làm tròn lên 0.5 mm
    end

    # Kiểm tra R; tự đổi R nếu không hợp lệ và trả về thông báo.
    def resolve_radius(a, b, w, back, r_req, n = nil)
      n = n.to_i
      n = DEFAULT_NOTCHES if n <= 0
      validate_back!(w, back)
      r_req = r_req.to_f
      r_max = [a.to_f, b.to_f].min / 2.0
      r_min = min_radius(w.to_f, back.to_f, n)
      if r_min > r_max + EPS
        raise ArgumentError, "Khung #{fmt(a)}x#{fmt(b)} quá nhỏ để bo góc với sắt rộng " \
                             "#{fmt(w)} (cần R tối thiểu #{fmt(r_min)} mm)"
      end
      msgs = []
      r = r_req
      if r < r_min - EPS
        r = r_min
        msgs << "Bán kính R=#{fmt(r_req)} mm nhỏ hơn mức tối thiểu cho sắt rộng #{fmt(w)} mm " \
                "với #{n} khía/góc. Đã tự đổi R = #{fmt(r)} mm."
      elsif r > r_max + EPS
        r = r_max
        msgs << "Bán kính R=#{fmt(r_req)} mm lớn hơn một nửa cạnh ngắn của khung. " \
                "Đã tự đổi R = #{fmt(r)} mm."
      end
      { r: r, r_requested: r_req, n: n, r_min: r_min, r_max: r_max,
        changed: !msgs.empty?, messages: msgs }
    end

    # Đường bao ngoài hình chữ nhật bo góc, bắt đầu ở giữa cạnh dưới (a/2, 0),
    # đi ngược chiều kim đồng hồ, khép kín (điểm cuối = điểm đầu).
    def rounded_rect_path(a, b, r, segs = 12)
      a = a.to_f; b = b.to_f; r = r.to_f
      pts = [[a / 2.0, 0.0], [a - r, 0.0]]
      add_arc = lambda do |cx, cy, a0|
        (1..segs).each do |k|
          ang = a0 + (Math::PI / 2.0) * k / segs
          pts << [cx + r * Math.cos(ang), cy + r * Math.sin(ang)]
        end
      end
      add_arc.call(a - r, r, -Math::PI / 2)
      pts << [a, b - r]
      add_arc.call(a - r, b - r, 0.0)
      pts << [r, b]
      add_arc.call(r, b - r, Math::PI / 2)
      pts << [0.0, r]
      add_arc.call(r, r, Math::PI)
      pts << [a / 2.0, 0.0]
      pts = pts.map { |x, y| [snap(x, [0.0, a, a / 2, r, a - r]), snap(y, [0.0, b, r, b - r])] }
      dedupe(pts)
    end

    def snap(v, targets)
      targets.each { |t| return t if (v - t).abs < 1e-9 }
      v
    end

    def dedupe(pts)
      out = []
      pts.each do |p|
        out << p if out.empty? || (p[0] - out[-1][0]).abs > EPS || (p[1] - out[-1][1]).abs > EPS
      end
      out
    end

    # Khoảng cách từ điểm (x,y) tới đường bao hình chữ nhật bo góc.
    def dist_to_rounded_rect(x, y, a, b, r)
      qx = (x - a / 2.0).abs - (a / 2.0 - r)
      qy = (y - b / 2.0).abs - (b / 2.0 - r)
      outside = Math.hypot([qx, 0].max, [qy, 0].max)
      inside  = [[qx, qy].max, 0].min
      (outside + inside - r).abs
    end

    # ---------------------------------------------------------------- trải phẳng
    def validate_back!(w, back)
      back = back.to_f
      unless back > 0 && back < w.to_f
        raise ArgumentError, "Độ dày lưng #{fmt(back)} mm phải > 0 và < bề rộng sắt #{fmt(w)} mm"
      end
      true
    end

    # Hình trải phẳng (mặt bên của thanh) trong hệ toạ độ 2D:
    #   y = 0     : mặt lưng (mặt ngoài khung, không cắt)
    #   y = back  : đường bản lề (đỉnh các khía V)
    #   y = w     : mặt trong khung (miệng khía)
    # notches: [{x:, angle:}]  — angle = góc gập (độ) tại khía.
    # end_left / end_right: góc (độ) của khía nửa ở hai đầu; 0 = đầu cắt vuông.
    def build_pattern(kind:, length:, w:, back:, notches:, end_left: 0.0, end_right: 0.0, extra: {})
      validate_back!(w, back)
      l = length.to_f; w = w.to_f; back = back.to_f
      d = w - back
      raise ArgumentError, 'Chiều dài khai triển phải > 0' unless l > 0
      ns = notches.map do |n|
        hw = d * Math.tan(n[:angle].to_f * Math::PI / 360.0)
        { x: n[:x].to_f, angle: n[:angle].to_f, hw: hw }
      end.sort_by { |n| n[:x] }
      hwl = d * Math.tan(end_left.to_f  * Math::PI / 360.0)
      hwr = d * Math.tan(end_right.to_f * Math::PI / 360.0)

      # kiểm tra miệng khía không chồng nhau
      spans = [[-Float::INFINITY, hwl]] + ns.map { |n| [n[:x] - n[:hw], n[:x] + n[:hw]] } +
              [[l - hwr, Float::INFINITY]]
      spans.each_cons(2) do |s1, s2|
        if s2[0] < s1[1] - EPS
          raise ArgumentError, "Các khía V chồng lên nhau tại x≈#{fmt(s2[0])} mm — " \
                               'tăng bán kính R hoặc giảm số khía'
        end
      end

      pts = [[0.0, 0.0], [l, 0.0]]
      if end_right.to_f > 0
        pts << [l, back] << [l - hwr, w]
      else
        pts << [l, w]
      end
      ns.reverse_each do |n|
        pts << [n[:x] + n[:hw], w] << [n[:x], back] << [n[:x] - n[:hw], w]
      end
      if end_left.to_f > 0
        pts << [hwl, w] << [0.0, back]
      else
        pts << [0.0, w]
      end
      pts = dedupe(pts)
      pts.pop if pts.size > 1 && (pts[-1][0] - pts[0][0]).abs < EPS && (pts[-1][1] - pts[0][1]).abs < EPS

      {
        kind: kind, length: l, w: w, back: back, depth: d,
        notches: ns, end_left: end_left.to_f, end_right: end_right.to_f,
        hw_left: hwl, hw_right: hwr, outline: pts, area: polygon_area(pts)
      }.merge(extra)
    end

    # Khung vát 45° làm từ 1 thanh: mối nối ở 1 góc (2 khía nửa 45° ở 2 đầu),
    # 3 khía V 90° ở 3 góc còn lại.
    def unfold_miter(a, b, w, back)
      validate_back!(w, back)
      la = a.to_f - 2 * back.to_f
      lb = b.to_f - 2 * back.to_f
      xs = [la, la + lb, 2 * la + lb]
      build_pattern(kind: 'miter', length: 2 * (la + lb), w: w, back: back,
                    notches: xs.map { |x| { x: x, angle: 90.0 } },
                    end_left: 90.0, end_right: 90.0,
                    extra: { a: a.to_f, b: b.to_f, segments: [la, lb, la, lb] })
    end

    # Khung bo góc kiểu A làm từ 1 thanh: mối nối ở giữa cạnh dưới (đầu cắt
    # vuông), mỗi góc bo có n khía V chia đều, tổng góc gập 90°/góc.
    # Chiều dài khai triển đo trên đường bản lề (bán kính r - back).
    def unfold_rounded(a, b, w, back, r, n)
      validate_back!(w, back)
      a = a.to_f; b = b.to_f; r = r.to_f; back = back.to_f; n = n.to_i
      raise ArgumentError, 'Số khía mỗi góc phải >= 1' if n < 1
      sa = a - 2 * r
      sb = b - 2 * r
      raise ArgumentError, "R=#{fmt(r)} lớn hơn nửa cạnh khung" if sa < -EPS || sb < -EPS
      sa = [sa, 0.0].max; sb = [sb, 0.0].max
      rh = r - back
      raise ArgumentError, "R=#{fmt(r)} phải lớn hơn độ dày lưng" unless rh > 0
      arc = rh * Math::PI / 2.0
      segs = [sa / 2.0, arc, sb, arc, sa, arc, sb, arc, sa / 2.0]
      notches = []
      x = 0.0
      segs.each_with_index do |len, i|
        if i.odd? # cung
          n.times { |k| notches << { x: x + (k + 0.5) * len / n, angle: 90.0 / n } }
        end
        x += len
      end
      build_pattern(kind: 'rounded', length: x, w: w, back: back, notches: notches,
                    extra: { a: a, b: b, r: r, n: n, segments: segs, arc_length: arc })
    end

    def polygon_area(pts)
      s = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        s += p[0] * q[1] - q[0] * p[1]
      end
      (s / 2.0).abs
    end

    # Hình trải phẳng theo thông tin khung (Hash có khoá chuỗi như attribute).
    def pattern_for(info, back: nil, n: nil)
      back = (back.nil? || back.to_f <= 0) ? (info['back'] || info['t']).to_f : back.to_f
      case info['type']
      when 'miter'
        unfold_miter(info['a'], info['b'], info['w'], back)
      when 'rounded'
        nn = (n.nil? || n.to_i <= 0) ? info['n'].to_i : n.to_i
        unfold_rounded(info['a'], info['b'], info['w'], back, info['r'], nn)
      else
        raise ArgumentError, "Không phải khung DIY Cắt Sắt (type=#{info['type'].inspect})"
      end
    end

    # ---------------------------------------------------------------- tối ưu cắt
    # pieces: [{label:, length:}] (mm). Trả về phương án dùng ít cây nhất giữa
    # First-Fit-Decreasing và Best-Fit-Decreasing.
    def optimize_cuts(pieces, stock: 6000.0, kerf: 2.0, trim: 0.0)
      stock = stock.to_f; kerf = kerf.to_f; trim = trim.to_f
      usable = stock - trim
      raise ArgumentError, 'Chiều dài cây phải > bỏ đầu cây' unless usable > 0
      raise ArgumentError, 'Mạch cắt không được âm' if kerf < 0
      list = pieces.map { |p| { label: p[:label].to_s, length: p[:length].to_f } }
      too_long = list.select { |p| p[:length] > usable + EPS }
      unless too_long.empty?
        raise ArgumentError, "Đoạn #{too_long.map { |p| "#{p[:label]} (#{fmt(p[:length])} mm)" }.join(', ')} " \
                             "dài hơn cây #{fmt(usable)} mm"
      end
      sorted = list.sort_by { |p| -p[:length] }
      plans = [:first, :best].map { |mode| pack(sorted, usable, kerf, mode) }
      bars = plans.min_by { |bs| [bs.size, -bs.map { |b| b[:remaining] }.max.to_f] }
      bars = bars.map do |bar|
        used = bar[:pieces].sum { |p| p[:length] }
        cuts = bar[:pieces].size
        kerf_loss = [stock - trim - used, kerf * cuts].min
        { pieces: bar[:pieces], used: used, kerf_loss: kerf_loss,
          waste: stock - used - kerf_loss - trim }
      end
      total_used = bars.sum { |b| b[:used] }
      {
        stock: stock, kerf: kerf, trim: trim, bars: bars, bar_count: bars.size,
        piece_count: list.size, total_piece_length: total_used,
        efficiency: bars.empty? ? 0.0 : total_used / (bars.size * stock)
      }
    end

    def pack(sorted, usable, kerf, mode)
      bars = []
      sorted.each do |p|
        fits = bars.select { |b| b[:remaining] >= p[:length] - EPS }
        bar = mode == :first ? fits.first : fits.min_by { |b| b[:remaining] }
        unless bar
          bar = { pieces: [], remaining: usable }
          bars << bar
        end
        bar[:pieces] << p
        bar[:remaining] = [bar[:remaining] - p[:length] - kerf, 0.0].max
      end
      bars
    end

    def plan_report(plan)
      lines = []
      lines << "Cây #{fmt(plan[:stock])} mm, mạch cắt #{fmt(plan[:kerf])} mm, bỏ đầu #{fmt(plan[:trim])} mm"
      lines << "Số đoạn: #{plan[:piece_count]}  —  Số cây cần: #{plan[:bar_count]}  —  " \
               "Hiệu suất: #{fmt(plan[:efficiency] * 100, 1)}%"
      plan[:bars].each_with_index do |bar, i|
        parts = bar[:pieces].map { |p| "#{p[:label]}=#{fmt(p[:length])}" }.join(' + ')
        lines << "Cây #{i + 1}: #{parts}  | thừa #{fmt(bar[:waste])} mm"
      end
      lines.join("\n")
    end

    # ---------------------------------------------------------------------- DXF
    # Xuất DXF R12 (ASCII), đơn vị mm. Nội dung chữ không dấu để mọi phần mềm CNC
    # đọc được.
    #  patterns: [{pattern:, title:}]
    LAYERS = { 'CAT' => 7, 'KHIA' => 1, 'BAN_LE' => 8, 'CHU' => 3, 'SO_DO_CAT' => 5 }.freeze

    def dxf_document(patterns, plan: nil)
      ents = []
      y0 = 0.0
      patterns.each do |item|
        pat = item[:pattern]
        dxf_pattern(ents, pat, 0.0, y0, item[:title].to_s)
        y0 -= pat[:w] + 60.0
      end
      dxf_plan(ents, plan, y0 - 40.0) if plan
      out = []
      out.concat(['0', 'SECTION', '2', 'HEADER',
                  '9', '$ACADVER', '1', 'AC1009',
                  '9', '$INSUNITS', '70', '4',
                  '0', 'ENDSEC'])
      out.concat(['0', 'SECTION', '2', 'TABLES', '0', 'TABLE', '2', 'LAYER', '70', LAYERS.size.to_s])
      LAYERS.each do |name, color|
        out.concat(['0', 'LAYER', '2', name, '70', '0', '62', color.to_s, '6', 'CONTINUOUS'])
      end
      out.concat(['0', 'ENDTAB', '0', 'ENDSEC'])
      out.concat(['0', 'SECTION', '2', 'ENTITIES'])
      out.concat(ents)
      out.concat(['0', 'ENDSEC', '0', 'EOF'])
      out.join("\r\n") + "\r\n"
    end

    def dxf_line(ents, layer, x1, y1, x2, y2)
      ents.concat(['0', 'LINE', '8', layer,
                   '10', n4(x1), '20', n4(y1), '30', '0.0',
                   '11', n4(x2), '21', n4(y2), '31', '0.0'])
    end

    def dxf_text(ents, layer, x, y, h, s)
      ents.concat(['0', 'TEXT', '8', layer, '10', n4(x), '20', n4(y), '30', '0.0',
                   '40', n4(h), '1', ascii(s)])
    end

    def n4(v)
      format('%.4f', v.to_f)
    end

    VN_MAP = {
      'àáạảãâầấậẩẫăằắặẳẵ' => 'a', 'èéẹẻẽêềếệểễ' => 'e', 'ìíịỉĩ' => 'i',
      'òóọỏõôồốộổỗơờớợởỡ' => 'o', 'ùúụủũưừứựửữ' => 'u', 'ỳýỵỷỹ' => 'y', 'đ' => 'd',
      'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ' => 'A', 'ÈÉẸẺẼÊỀẾỆỂỄ' => 'E', 'ÌÍỊỈĨ' => 'I',
      'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ' => 'O', 'ÙÚỤỦŨƯỪỨỰỬỮ' => 'U', 'ỲÝỴỶỸ' => 'Y', 'Đ' => 'D',
      '°' => 'deg'
    }.freeze

    def ascii(s)
      s = s.to_s.dup
      VN_MAP.each { |from, to| s = s.tr(from, to * from.length) if to.length == 1 }
      s = s.gsub('°', 'deg')
      s.encode('ASCII', invalid: :replace, undef: :replace, replace: '?')
    end

    def dxf_pattern(ents, pat, ox, oy, title)
      pts = pat[:outline]
      w = pat[:w]; back = pat[:back]
      notch_seg = lambda do |p, q|
        # cạnh khía: một đầu ở đường bản lề (y = back), đầu kia ở miệng (y = w),
        # và không phải cạnh đứng ở đầu thanh
        ys = [p[1], q[1]].sort
        (ys[0] - back).abs < EPS && (ys[1] - w).abs < EPS && (p[0] - q[0]).abs > EPS
      end
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        layer = notch_seg.call(p, q) ? 'KHIA' : 'CAT'
        dxf_line(ents, layer, ox + p[0], oy + p[1], ox + q[0], oy + q[1])
      end
      # đường bản lề (tham khảo, không cắt)
      dxf_line(ents, 'BAN_LE', ox, oy + back, ox + pat[:length], oy + back)
      label = "#{title} | L=#{fmt(pat[:length])} | W=#{fmt(w)} | LUNG=#{fmt(back)} | " \
              "SAU KHIA=#{fmt(pat[:depth])} | #{pat[:notches].size} KHIA"
      dxf_text(ents, 'CHU', ox, oy + w + 6.0, 5.0, label)
      pat[:notches].each_with_index do |n, i|
        dxf_text(ents, 'CHU', ox + n[:x] - 4.0, oy - 8.0, 3.0,
                 "#{i + 1}:#{fmt(n[:x], 1)}/#{fmt(n[:angle], 1)}deg")
      end
    end

    def dxf_plan(ents, plan, y_top)
      hbar = 20.0
      dxf_text(ents, 'CHU', 0, y_top + 8.0, 6.0,
               "SO DO CAT: #{plan[:bar_count]} cay x #{fmt(plan[:stock])} mm, mach cat #{fmt(plan[:kerf])}")
      plan[:bars].each_with_index do |bar, i|
        y = y_top - i * (hbar + 25.0) - hbar
        s = plan[:stock]
        [[0, y, s, y], [s, y, s, y + hbar], [s, y + hbar, 0, y + hbar], [0, y + hbar, 0, y]].each do |l|
          dxf_line(ents, 'SO_DO_CAT', *l)
        end
        x = plan[:trim]
        bar[:pieces].each do |p|
          x += p[:length]
          dxf_line(ents, 'SO_DO_CAT', x, y, x, y + hbar)
          dxf_text(ents, 'CHU', x - p[:length] + 5.0, y + 6.0, 5.0, "#{p[:label]} #{fmt(p[:length])}")
          x += plan[:kerf]
        end
        dxf_text(ents, 'CHU', s + 10.0, y + 6.0, 5.0, "Cay #{i + 1} thua #{fmt(bar[:waste])}")
      end
    end

    def write_text(path, text)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp"
      File.open(tmp, 'wb') { |f| f.write(text) }
      File.delete(path) if File.exist?(path)
      File.rename(tmp, path)
      path
    end
  end

  # ===========================================================================
  #  (1) THƯ VIỆN QUY CÁCH — JSON
  # ===========================================================================
  class Library
    DEFAULTS = [
      [13, 26, 1.0], [20, 20, 1.0], [20, 40, 1.2], [25, 25, 1.2], [25, 50, 1.4],
      [30, 30, 1.2], [30, 60, 1.4], [40, 40, 1.4], [40, 80, 1.8], [50, 50, 1.8]
    ].freeze

    attr_reader :path, :profiles, :last_error

    def self.default_path
      base = ENV['APPDATA'] ? File.join(ENV['APPDATA'], 'DIYCatSat') : File.join(Dir.home, '.diy_cat_sat')
      File.join(base, 'quy_cach_sat_hop.json')
    end

    def initialize(path = nil)
      @path = path || self.class.default_path
      @last_error = nil
      reload
    end

    def reload
      if File.exist?(@path)
        data = JSON.parse(File.read(@path, encoding: 'UTF-8'))
        list = data.is_a?(Hash) ? data['profiles'] : data
        raise JSON::ParserError, 'thiếu danh sách "profiles"' unless list.is_a?(Array)
        @profiles = list.map do |p|
          begin
            Core.normalize_profile(p)
          rescue ArgumentError, TypeError => e
            @last_error = "Bỏ qua quy cách lỗi #{p.inspect}: #{e.message}"
            nil
          end
        end.compact
      else
        load_defaults
        save
      end
      self
    rescue JSON::ParserError => e
      @last_error = "File thư viện hỏng (#{e.message}); đã lưu bản sao .bak và nạp mặc định"
      FileUtils.cp(@path, "#{@path}.bak") rescue nil
      load_defaults
      save
      self
    end

    def load_defaults
      @profiles = DEFAULTS.map { |w, h, t| Core.normalize_profile('w' => w, 'h' => h, 't' => t) }
    end

    def save
      data = { 'plugin' => 'DIYCatSat', 'version' => VERSION, 'unit' => 'mm', 'profiles' => @profiles }
      Core.write_text(@path, JSON.pretty_generate(data))
    end

    # Thêm hoặc sửa (cùng tên thì ghi đè). Trả về quy cách đã chuẩn hoá.
    def add(w, h, t, name = nil)
      p = Core.normalize_profile('name' => name, 'w' => w, 'h' => h, 't' => t)
      idx = @profiles.index { |q| q['name'] == p['name'] }
      idx ? @profiles[idx] = p : @profiles << p
      @profiles.sort_by! { |q| [q['w'] * q['h'], q['w'], q['t']] }
      save
      p
    end

    def remove(name)
      before = @profiles.size
      @profiles.reject! { |q| q['name'] == name.to_s }
      save if @profiles.size != before
      before != @profiles.size
    end

    def find(name)
      @profiles.find { |q| q['name'] == name.to_s }
    end

    def names
      @profiles.map { |q| q['name'] }
    end
  end

  # ===========================================================================
  #  Thông báo (có chế độ im lặng cho test)
  # ===========================================================================
  @silent = false
  @warnings = []
  @library = nil

  class << self
    attr_accessor :silent

    def warnings
      @warnings ||= []
    end

    def clear_warnings
      @warnings = []
    end

    def notify(msg)
      warnings << msg
      puts "[DIYCatSat] #{msg}"
      UI.messagebox(msg) if !silent && defined?(UI)
    end

    def library(path = nil)
      @library = Library.new(path) if path || @library.nil?
      @library
    end

    def resolve_profile(profile)
      p = profile.is_a?(Hash) ? Core.normalize_profile(profile) : library.find(profile)
      raise ArgumentError, "Không có quy cách #{profile.inspect} trong thư viện" unless p
      p
    end
  end

  # ===========================================================================
  #  (2)(3) DỰNG HÌNH TRONG SKETCHUP
  # ===========================================================================
  module Build
    module_function

    def pt(x, y, z = 0.0)
      Geom::Point3d.new(x.to_f.mm, y.to_f.mm, z.to_f.mm)
    end

    def model
      Sketchup.active_model
    end

    def set_info(ent, info)
      info.each { |k, v| ent.set_attribute(DICT, k.to_s, v) }
    end

    def info(ent)
      return nil unless ent.respond_to?(:attribute_dictionary)
      dict = ent.attribute_dictionary(DICT)
      return nil unless dict
      h = {}
      dict.each_pair { |k, v| h[k] = v }
      h['type'] ? h : nil
    end

    def frame?(ent)
      i = info(ent)
      !i.nil? && %w[miter rounded].include?(i['type'])
    end

    def operation(name)
      m = model
      m.start_operation(name, true)
      begin
        result = yield
        m.commit_operation
        result
      rescue StandardError
        m.abort_operation
        raise
      end
    end

    def place(group, origin)
      return group if origin.nil?
      group.transform!(Geom::Transformation.translation(Geom::Vector3d.new(*origin.map { |v| v.to_f.mm })))
      group
    end

    def face_up(face)
      face.reverse! if face.normal.z < 0
      face
    end

    # ---- (2a) khung vát 45°: 4 khối hình thang đặc
    def miter_frame(a, b, profile, origin: nil)
      prof = DIYCatSat.resolve_profile(profile)
      w = prof['w']; h = prof['h']; t = prof['t']
      bars = Core.miter_bars(a, b, w)
      operation('DIY: Khung vát 45°') do
        frame = model.active_entities.add_group
        frame.name = "Khung vat 45 #{Core.fmt(a)}x#{Core.fmt(b)} (#{prof['name']})"
        bars.each do |bar|
          g = frame.entities.add_group
          g.name = "Thanh #{bar[:name]} #{Core.fmt(bar[:outer])}"
          face = g.entities.add_face(bar[:poly].map { |x, y| pt(x, y, 0) })
          raise "Không tạo được mặt hình thang cho thanh #{bar[:name]}" unless face
          face_up(face).pushpull(h.to_f.mm)
          set_info(g, 'type' => 'miter_bar', 'outer' => bar[:outer], 'inner' => bar[:inner],
                      'w' => w, 'h' => h, 't' => t)
        end
        set_info(frame, 'type' => 'miter', 'a' => a.to_f, 'b' => b.to_f, 'w' => w, 'h' => h, 't' => t,
                        'profile' => prof['name'], 'back' => t, 'version' => VERSION)
        place(frame, origin)
      end
    end

    # ---- (2b) khung bo góc kiểu A: tiết diện ống quét theo đường bao ngoài
    def rounded_frame(a, b, profile, r, n: nil, back: nil, origin: nil, segs: 12)
      prof = DIYCatSat.resolve_profile(profile)
      w = prof['w']; h = prof['h']; t = prof['t']
      back = (back.nil? || back.to_f <= 0) ? t : back.to_f
      res = Core.resolve_radius(a, b, w, back, r, n)
      res[:messages].each { |m| DIYCatSat.notify(m) }
      rr = res[:r]
      a = a.to_f; b = b.to_f
      operation('DIY: Khung bo góc kiểu A') do
        frame = model.active_entities.add_group
        frame.name = "Khung bo goc R#{Core.fmt(rr)} #{Core.fmt(a)}x#{Core.fmt(b)} (#{prof['name']})"
        ents = frame.entities

        # Đường dẫn = đường bao ngoài mặt đáy, vẽ TRONG CÙNG group với tiết diện.
        path_pts = Core.rounded_rect_path(a, b, rr, segs)
        path = ents.add_edges(path_pts.map { |x, y| pt(x, y, 0) }).compact
        raise 'Không tạo được đường dẫn followme' if path.empty?

        # Tiết diện ống ở giữa cạnh dưới, vuông góc với đường dẫn; góc ngoài-đáy
        # của tiết diện nằm trên đường dẫn.
        xm = a / 2.0
        outer = ents.add_face([pt(xm, 0, 0), pt(xm, w, 0), pt(xm, w, h), pt(xm, 0, h)])
        raise 'Không tạo được mặt tiết diện' unless outer
        hole = ents.add_face([pt(xm, t, t), pt(xm, w - t, t), pt(xm, w - t, h - t), pt(xm, t, h - t)])
        hole.erase! if hole && hole.valid? && hole != outer
        section = ents.grep(Sketchup::Face).find { |f| f.valid? && f.loops.size == 2 } || outer
        ok = section.followme(path)
        raise 'followme thất bại khi dựng khung bo góc' unless ok

        remove_internal_faces(ents)
        soften_curves(ents, 20.0)
        set_info(frame, 'type' => 'rounded', 'a' => a, 'b' => b, 'r' => rr, 'r_requested' => res[:r_requested],
                        'r_changed' => res[:changed], 'n' => res[:n], 'w' => w, 'h' => h, 't' => t,
                        'back' => back, 'profile' => prof['name'], 'path_segments' => path_pts.size - 1,
                        'developed_length' => Core.unfold_rounded(a, b, w, back, rr, res[:n])[:length],
                        'version' => VERSION)
        place(frame, origin)
      end
    end

    # Mặt mà mọi cạnh đều có >= 3 mặt kề là vách trong (ví dụ tiết diện còn sót
    # sau followme khép kín) — xoá mặt, KHÔNG xoá cạnh.
    def remove_internal_faces(ents)
      ents.grep(Sketchup::Face).select { |f| f.edges.all? { |e| e.faces.size >= 3 } }.each do |f|
        f.erase! if f.valid?
      end
    end

    def soften_curves(ents, max_deg)
      lim = max_deg * Math::PI / 180.0
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.faces.size == 2
        ang = e.faces[0].normal.angle_between(e.faces[1].normal)
        next unless ang > 1e-6 && ang < lim
        e.soft = true
        e.smooth = true
      end
    end

    # ---- (3) trải phẳng
    def unfold(frame, back: nil, n: nil, origin: nil)
      inf = info(frame)
      raise ArgumentError, 'Hãy chọn một khung do DIY Cắt Sắt dựng' unless inf && frame?(frame)
      pat = Core.pattern_for(inf, back: back, n: n)
      operation('DIY: Trải phẳng khía V') do
        g = model.active_entities.add_group
        g.name = "Trai phang #{inf['type']} L=#{Core.fmt(pat[:length])} lung=#{Core.fmt(pat[:back])}"
        face = g.entities.add_face(pat[:outline].map { |x, y| pt(x, y, 0) })
        raise 'Không tạo được mặt trải phẳng' unless face
        face_up(face)
        g.entities.add_line(pt(0, pat[:back], 0), pt(pat[:length], pat[:back], 0))
        set_info(g, 'type' => 'flat', 'kind' => pat[:kind], 'length' => pat[:length], 'w' => pat[:w],
                    'back' => pat[:back], 'notches' => pat[:notches].size, 'area' => pat[:area])
        frame.set_attribute(DICT, 'back', pat[:back])
        frame.set_attribute(DICT, 'n', pat[:n]) if pat[:n]
        if origin.nil?
          o = frame.transformation.origin
          origin = [o.x.to_mm, o.y.to_mm - pat[:w] - 80.0, 0.0]
        end
        place(g, origin)
        { group: g, pattern: pat }
      end
    end
  end

  # ===========================================================================
  #  (4) TỐI ƯU CẮT + DXF — API dùng chung cho UI và test
  # ===========================================================================
  class << self
    def frame_infos(frames)
      frames.map { |f| f.is_a?(Hash) ? f : Build.info(f) }.compact.select { |i| %w[miter rounded].include?(i['type']) }
    end

    # miter_mode: :bars = khung vát cắt 4 thanh rời; :one_piece = 1 thanh khía V.
    # Khung bo góc LUÔN dùng chiều dài khai triển (1 thanh).
    def cut_pieces(frames, qty: 1, back: nil, miter_mode: :bars)
      pieces = []
      frame_infos(frames).each_with_index do |inf, fi|
        tag = "K#{fi + 1}"
        qty.to_i.times do |q|
          sfx = qty.to_i > 1 ? ".#{q + 1}" : ''
          if inf['type'] == 'miter' && miter_mode.to_s != 'one_piece'
            Core.miter_bars(inf['a'], inf['b'], inf['w']).each do |bar|
              pieces << { label: "#{tag}#{sfx}-#{bar[:name]}", length: bar[:outer] }
            end
          else
            pat = Core.pattern_for(inf, back: back)
            pieces << { label: "#{tag}#{sfx}-#{inf['type'] == 'rounded' ? 'BoGoc' : 'Khia'}",
                        length: pat[:length] }
          end
        end
      end
      pieces
    end

    def cut_plan(frames, stock: 6000.0, kerf: 2.0, trim: 0.0, qty: 1, back: nil, miter_mode: :bars)
      pieces = cut_pieces(frames, qty: qty, back: back, miter_mode: miter_mode)
      raise ArgumentError, 'Không có khung nào để tính cắt' if pieces.empty?
      Core.optimize_cuts(pieces, stock: stock, kerf: kerf, trim: trim)
    end

    # back: độ dày lưng NHẬP VÀO; nil/0 => độ dày lưng đã lưu trên khung (mặc
    # định = t). Không hard-code.
    def export_dxf(path, frames, back: nil, plan: nil)
      items = frame_infos(frames).each_with_index.map do |inf, i|
        pat = Core.pattern_for(inf, back: back)
        title = inf['type'] == 'miter' ? "K#{i + 1} VAT 45 #{Core.fmt(inf['a'])}x#{Core.fmt(inf['b'])}" :
                                         "K#{i + 1} BO GOC R#{Core.fmt(inf['r'])} #{Core.fmt(inf['a'])}x#{Core.fmt(inf['b'])}"
        { pattern: pat, title: "#{title} #{inf['profile']}" }
      end
      raise ArgumentError, 'Không có khung nào để xuất DXF' if items.empty?
      Core.write_text(path, Core.dxf_document(items, plan: plan))
    end
  end

  # ===========================================================================
  #  GIAO DIỆN
  # ===========================================================================
  module UIx
    module_function

    def guard
      yield
    rescue StandardError => e
      UI.messagebox("DIY Cắt Sắt — lỗi:\n#{e.message}")
      puts e.backtrace.first(8).join("\n")
    end

    def selected_frames
      m = Sketchup.active_model
      sel = m.selection.to_a.select { |e| Build.frame?(e) }
      sel = m.entities.to_a.select { |e| Build.frame?(e) } if sel.empty?
      sel
    end

    def next_origin
      bb = Sketchup.active_model.bounds
      bb.empty? ? [0.0, 0.0, 0.0] : [bb.max.x.to_mm + 200.0, bb.min.y.to_mm, 0.0]
    end

    def tool_library
      guard do
        lib = DIYCatSat.library
        res = UI.inputbox(['Thao tác', 'Tên (để trống = tự đặt)', 'W (mm)', 'H (mm)', 'Độ dày thành t (mm)'],
                          ['Xem danh sách', '', 25.0, 25.0, 1.2],
                          ['Xem danh sách|Thêm / sửa|Xoá theo tên', '', '', '', ''],
                          'Thư viện quy cách sắt hộp')
        next unless res
        act, name, w, h, t = res
        case act
        when 'Thêm / sửa'
          p = lib.add(w, h, t, name)
          UI.messagebox("Đã lưu quy cách #{p['name']}\n#{lib.path}")
        when 'Xoá theo tên'
          UI.messagebox(lib.remove(name) ? "Đã xoá #{name}" : "Không thấy quy cách #{name}")
        else
          UI.messagebox("File: #{lib.path}\n\n" + lib.profiles.map { |p|
            "#{p['name']}   (W #{Core.fmt(p['w'])}, H #{Core.fmt(p['h'])}, t #{Core.fmt(p['t'])})"
          }.join("\n"))
        end
      end
    end

    def tool_frame
      guard do
        names = DIYCatSat.library.names
        raise 'Thư viện quy cách trống' if names.empty?
        default = names.include?('25x25x1.2') ? '25x25x1.2' : names.first
        res = UI.inputbox(['Kiểu khung', 'Rộng A (mm)', 'Cao B (mm)', 'Quy cách sắt', 'Bán kính R (mm, bo góc)',
                           'Số khía mỗi góc (0 = tự động)'],
                          ['Vát 45°', 400.0, 400.0, default, 50.0, 0],
                          ['Vát 45°|Bo góc kiểu A', '', '', names.join('|'), '', ''],
                          'Dựng khung sắt hộp')
        next unless res
        kind, a, b, prof, r, n = res
        if kind == 'Vát 45°'
          DIYCatSat::Build.miter_frame(a, b, prof, origin: next_origin)
        else
          DIYCatSat::Build.rounded_frame(a, b, prof, r, n: n, origin: next_origin)
        end
      end
    end

    def tool_unfold
      guard do
        frames = selected_frames
        raise 'Hãy chọn một khung do DIY Cắt Sắt dựng' if frames.empty?
        frames.each do |f|
          inf = Build.info(f)
          res = UI.inputbox(['Độ dày lưng (mm)', 'Số khía mỗi góc (bo góc; 0 = giữ nguyên)'],
                            [(inf['back'] || inf['t']).to_f, 0],
                            "Trải phẳng: #{f.name}")
          next unless res
          out = Build.unfold(f, back: res[0], n: res[1])
          pat = out[:pattern]
          UI.messagebox("#{f.name}\nChiều dài khai triển: #{Core.fmt(pat[:length])} mm\n" \
                        "Độ dày lưng: #{Core.fmt(pat[:back])} mm — sâu khía: #{Core.fmt(pat[:depth])} mm\n" \
                        "Vị trí khía (mm/góc):\n" +
                        pat[:notches].map { |nn| "  #{Core.fmt(nn[:x], 1)} / #{Core.fmt(nn[:angle], 1)}°" }.join("\n"))
        end
      end
    end

    def tool_cut
      guard do
        frames = selected_frames
        raise 'Không có khung DIY Cắt Sắt nào trong mô hình' if frames.empty?
        res = UI.inputbox(['Chiều dài cây (mm)', 'Mạch cắt (mm)', 'Bỏ đầu cây (mm)', 'Số bộ khung',
                           'Khung vát 45° cắt', 'Độ dày lưng (mm, 0 = theo khung)', 'Xuất DXF'],
                          [6000.0, 2.0, 0.0, 1, '4 thanh rời', 0.0, 'Có'],
                          ['', '', '', '', '4 thanh rời|1 thanh khía V', '', 'Có|Không'],
                          'Tối ưu cắt cây sắt')
        next unless res
        stock, kerf, trim, qty, mode, back, dxf = res
        back = back.to_f > 0 ? back.to_f : nil
        mmode = mode == '1 thanh khía V' ? :one_piece : :bars
        plan = DIYCatSat.cut_plan(frames, stock: stock, kerf: kerf, trim: trim, qty: qty, back: back,
                                          miter_mode: mmode)
        msg = Core.plan_report(plan)
        if dxf == 'Có'
          path = UI.savepanel('Lưu DXF', '', 'diy_cat_sat.dxf')
          if path
            path += '.dxf' unless path.downcase.end_with?('.dxf')
            DIYCatSat.export_dxf(path, frames, back: back, plan: plan)
            msg += "\n\nĐã xuất DXF: #{path}"
          end
        end
        UI.messagebox(msg)
      end
    end
  end

  if defined?(UI) && defined?(Sketchup) && !file_loaded?('diy_cat_sat_v2')
    menu = UI.menu('Extensions').add_submenu("DIY Cắt Sắt v#{VERSION}")
    menu.add_item('1. Thư viện quy cách sắt hộp') { UIx.tool_library }
    menu.add_item('2. Dựng khung (vát 45° / bo góc)') { UIx.tool_frame }
    menu.add_item('3. Trải phẳng khía rãnh V') { UIx.tool_unfold }
    menu.add_item('4. Tối ưu cắt cây 6m + DXF') { UIx.tool_cut }
    file_loaded('diy_cat_sat_v2')
  end
end
