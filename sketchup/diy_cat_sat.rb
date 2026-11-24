# Tên file: diy_cat_sat.rb  (v1.1 - bản đã sửa lỗi)
# Tương thích: SketchUp 2017+ (đã viết cho SketchUp 2023 / Ruby 2.7)
# Lưu file dạng UTF-8 (KHÔNG BOM).

require 'sketchup.rb'

module DIYSteelCutList
  EPS = 0.01 # mm

  # ---------------------------------------------------------------
  # 1. ĐO KÍCH THƯỚC
  # ---------------------------------------------------------------

  # Độ dài thật của 1 trục (Transformation#xaxis trả về vector ĐÃ CHUẨN HOÁ,
  # nên không dùng được để lấy tỷ lệ scale -> phải đọc ma trận to_a).
  def self.axis_scales(tr)
    a = tr.to_a
    [
      Math.sqrt(a[0]**2 + a[1]**2 + a[2]**2),
      Math.sqrt(a[4]**2 + a[5]**2 + a[6]**2),
      Math.sqrt(a[8]**2 + a[9]**2 + a[10]**2)
    ]
  end

  def self.definition_of(ent)
    ent.respond_to?(:definition) ? ent.definition : ent.entities.parent
  end

  def self.container?(e)
    e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
  end

  # Bounding box chỉ tính Face/Edge (bỏ đường dóng, text, kích thước...)
  def self.geometry_bounds(defn)
    bb = Geom::BoundingBox.new
    defn.entities.each do |e|
      next unless e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
      bb.add(e.bounds)
    end
    bb
  end

  # Duyệt đệ quy: chọn cả khung (group lồng nhau) vẫn ra được từng thanh.
  # Thanh "lá" = group/component không chứa group/component con.
  def self.collect_bars(ents, parent_tr, out)
    ents.each do |e|
      next unless container?(e) && e.visible? && (e.layer.nil? || e.layer.visible?)
      tr = parent_tr * e.transformation
      children = definition_of(e).entities.select { |c| container?(c) }
      if children.empty?
        out << [e, tr]
      else
        collect_bars(definition_of(e).entities, tr, out)
      end
    end
    out
  end

  # Trả về [cạnh nhỏ, cạnh lớn, chiều dài] (mm), đo theo trục CỤC BỘ.
  # Lưu ý: chỉ đúng khi trục của group/component chạy dọc theo thanh.
  def self.local_dims(ent, tr)
    bb = geometry_bounds(definition_of(ent))
    return nil if bb.empty?
    sx, sy, sz = axis_scales(tr)
    [bb.width.to_mm * sx, bb.height.to_mm * sy, bb.depth.to_mm * sz]
      .map { |v| v.round(1) }.sort
  end

  # Tên quy cách: ưu tiên tên Component/Group nếu có dạng "25x25" / "40x20x1.4"
  # (để phân biệt độ dày thành ống - hình học không đọc ra được).
  def self.profile_name(ent, w, h)
    name = ent.name.to_s.strip
    name = definition_of(ent).name.to_s.strip if name.empty? && ent.is_a?(Sketchup::ComponentInstance)
    if name =~ /(\d+(?:[.,]\d+)?\s*[xX×*]\s*\d+(?:[.,]\d+)?(?:\s*[xX×*]\s*\d+(?:[.,]\d+)?)?)/
      return $1.gsub(/\s+/, '').tr('X×*,', 'xxx.')
    end
    "#{w.round}x#{h.round}"
  end

  # ---------------------------------------------------------------
  # 2. TỐI ƯU CẮT 1D  (Best Fit Decreasing + kiểm tra cận dưới)
  #    pieces: [{len:, tag:}] ; n đoạn trên 1 cây cần n mạch cắt
  #    (đoạn cuối vẫn phải cắt tách khỏi phần dư), trừ khi vừa khít.
  # ---------------------------------------------------------------
  def self.optimize_1d(pieces, usable, kerf)
    bars = []
    pieces.sort_by { |p| -p[:len] }.each do |p|
      best = nil
      best_rem = nil
      bars.each do |b|
        rem = usable - (b[:sum] + p[:len] + kerf * b[:cuts].size) # kerf giữa các đoạn
        next if rem < -EPS
        if best_rem.nil? || rem < best_rem
          best, best_rem = b, rem
        end
      end
      best ||= (bars << { sum: 0.0, cuts: [] }).last
      best[:sum] += p[:len]
      best[:cuts] << p
    end
    bars.each do |b|
      used = b[:sum] + kerf * (b[:cuts].size - 1)
      left = usable - used
      b[:offcut] = left > kerf ? (left - kerf) : 0.0 # trừ mạch cắt tách phần dư
    end
    lower = (pieces.sum { |p| p[:len] + kerf } / (usable + kerf)).ceil
    [bars, lower]
  end

  # ---------------------------------------------------------------
  # 3. VẼ SƠ ĐỒ (tất cả nằm trong 1 group "SO_DO_CAT_PHOI" để dễ xoá)
  # ---------------------------------------------------------------
  PALETTE = [[66,133,244],[52,168,83],[251,188,5],[234,67,53],[0,172,193],
             [171,71,188],[255,112,67],[124,179,66],[92,107,192],[141,110,99]]

  def self.material(model, name, rgb)
    model.materials[name] || model.materials.add(name).tap { |m| m.color = Sketchup::Color.new(*rgb) }
  end

  def self.add_box(ents, x, y, len_mm, w_mm, h_mm, mat)
    g = ents.add_group
    f = g.entities.add_face([x, y, 0], [x + len_mm.mm, y, 0],
                            [x + len_mm.mm, y - w_mm.mm, 0], [x, y - w_mm.mm, 0])
    f.reverse! if f.normal.z < 0
    f.pushpull(h_mm.mm)
    g.material = mat
    g
  end

  def self.draw(model, results, stock, trim, kerf)
    origin_bb = model.bounds
    diag = model.entities.add_group
    diag.name = "SO_DO_CAT_PHOI #{Time.now.strftime('%Y-%m-%d %H:%M')}"
    ents = diag.entities

    x0 = origin_bb.empty? ? 0.0 : origin_bb.min.x
    y = origin_bb.empty? ? 0.0 : origin_bb.min.y - 1000.mm
    scrap = material(model, "DIY_Phe_lieu", [220, 220, 220])
    trim_mat = material(model, "DIY_Cat_dau", [90, 90, 90])

    results.each do |prof, r|
      bw = [r[:w], 20].max
      bh = [r[:h], 20].max
      ents.add_text("QUY CÁCH #{prof}: #{r[:bars].size} cây #{stock.round}mm", [x0, y + 150.mm, 0])

      # Cùng chiều dài -> cùng màu (thợ dễ nhận diện)
      color_of = {}
      r[:bars].each_with_index do |b, i|
        x = x0
        if trim > EPS
          add_box(ents, x, y, trim, bw, bh, trim_mat)
          x += (trim + kerf).mm
        end
        b[:cuts].each do |c|
          key = c[:len].round(1)
          color_of[key] ||= material(model, "DIY_#{prof}_#{key}", PALETTE[color_of.size % PALETTE.size])
          add_box(ents, x, y, c[:len], bw, bh, color_of[key])
          ents.add_text("#{key}", [x + (c[:len] / 2.0).mm, y - (bw / 2.0).mm, bh.mm])
          x += (c[:len] + kerf).mm
        end
        stock_end = x0 + stock.mm - (trim > EPS ? trim.mm : 0)
        add_box(ents, x, y, (stock_end - x).to_mm, bw, bh, scrap) if (stock_end - x).to_mm > 1.0
        add_box(ents, stock_end, y, trim, bw, bh, trim_mat) if trim > EPS

        cuts = b[:cuts].map { |c| c[:len].round(1) }.join(' + ')
        ents.add_text("Cây #{i + 1}: #{cuts} | Dư dùng được: #{b[:offcut].round(1)} mm",
                      [x0 + stock.mm + 100.mm, y - 10.mm, 0])
        y -= (bw + 150).mm
      end
      y -= 400.mm
    end
    diag
  end

  # ---------------------------------------------------------------
  # 4. CHẠY CHÍNH
  # ---------------------------------------------------------------
  def self.run_tool
    model = Sketchup.active_model
    sel = model.selection.select { |e| container?(e) }
    if sel.empty?
      UI.messagebox("Vui lòng chọn các thanh sắt (Group/Component) hoặc cả khung trước khi chạy!")
      return
    end

    prompts = ["Chiều dài cây phôi (mm):", "Mạch cắt / lưỡi cắt (mm):", "Cắt bỏ MỖI đầu cây (mm):"]
    input = UI.inputbox(prompts, [6000.0, 2.0, 0.0], "Cấu hình cắt phôi sắt DIY")
    return unless input
    stock, kerf, trim = input.map(&:to_f)
    usable = stock - (trim > EPS ? 2 * (trim + kerf) : 0.0)
    if stock <= 0 || kerf < 0 || trim < 0 || usable <= 0
      UI.messagebox("Thông số không hợp lệ.")
      return
    end

    # Toạ độ cha của vùng đang chọn (khi đang mở edit 1 group)
    parent_tr = model.edit_transform || Geom::Transformation.new
    leaf = collect_bars(sel, parent_tr, [])

    groups = {}
    warnings = []
    leaf.each do |ent, tr|
      d = local_dims(ent, tr)
      next unless d
      w, h, len = d
      prof = profile_name(ent, w, h)
      warnings << "- '#{ent.name}' (#{d.join('x')}): chiều dài < 3 lần tiết diện, kiểm tra lại" if len < 3 * h
      (groups[prof] ||= { w: w, h: h, pieces: [] })[:pieces] << { len: len, tag: ent.name }
    end

    results = {}
    report = ["=== BÁO CÁO CẮT PHÔI (phôi #{stock.round} mm, dùng được #{usable.round(1)} mm) ==="]
    total_bars = 0
    groups.sort.each do |prof, g|
      over, ok = g[:pieces].partition { |p| p[:len] > usable + EPS }
      bars, lower = optimize_1d(ok, usable, kerf)
      results[prof] = g.merge(bars: bars)
      total_bars += bars.size
      metres = g[:pieces].sum { |p| p[:len] } / 1000.0
      waste = bars.sum { |b| b[:offcut] }
      status = bars.size == lower ? "tối ưu" : "cận dưới #{lower} cây"
      report << "\n• #{prof}: #{g[:pieces].size} đoạn, #{metres.round(2)} m -> #{bars.size} cây (#{status}), dư #{(waste / 1000).round(2)} m"
      report << "  (!) #{over.size} đoạn dài hơn cây phôi: #{over.map { |p| p[:len] }.join(', ')} mm" unless over.empty?
    end
    report << "\nTỔNG: #{total_bars} cây cần mua"
    report += ["\nCẢNH BÁO:"] + warnings.first(10) unless warnings.empty?

    model.start_operation("Tối ưu cắt phôi sắt", true)
    begin
      draw(model, results, stock, trim, kerf)
      model.commit_operation
    rescue => e
      model.abort_operation
      UI.messagebox("Lỗi: #{e.message}")
      raise
    end
    UI.messagebox(report.join("\n"), MB_MULTILINE, "Kết quả tính phôi DIY")
  end

  unless file_loaded?(__FILE__)
    cmd = UI::Command.new("Tối ưu cắt phôi sắt") { run_tool }
    cmd.tooltip = "Bóc tách kích thước & tối ưu cắt cây sắt 6m"
    cmd.status_bar_text = "Chọn các thanh sắt hoặc cả khung rồi bấm"
    UI.menu("Extensions").add_item(cmd)
    tb = UI::Toolbar.new("DIY Cơ Khí")
    tb.add_item(cmd)
    tb.get_last_state == TB_NEVER_SHOWN ? tb.show : tb.restore
    file_loaded(__FILE__)
  end
end
