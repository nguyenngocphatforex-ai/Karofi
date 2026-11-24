# encoding: UTF-8
# Kiểm thử phần Core (không cần SketchUp):  ruby dev_tests/core_test.rb
require 'minitest/autorun'
require 'tmpdir'
require_relative '../diy_cat_sat'

class CoreTest < Minitest::Test
  C = DIYCatSat::Core

  def test_library_roundtrip
    Dir.mktmpdir do |d|
      path = File.join(d, 'lib.json')
      lib = DIYCatSat::Library.new(path)
      assert File.exist?(path)
      assert lib.find('25x25x1.2')
      lib.add(30, 15, 1.1, 'abc')
      lib2 = DIYCatSat::Library.new(path)
      assert_equal 1.1, lib2.find('abc')['t']
      assert lib2.remove('abc')
      assert_nil DIYCatSat::Library.new(path).find('abc')
      assert_raises(ArgumentError) { lib2.add(25, 25, 13) }
      File.write(path, '{not json')
      lib3 = DIYCatSat::Library.new(path)
      assert lib3.last_error
      assert lib3.find('25x25x1.2')
    end
  end

  def test_miter_bars_trapezoid
    bars = C.miter_bars(400, 400, 25)
    assert_equal 4, bars.size
    bars.each do |b|
      assert_in_delta 9375.0, C.polygon_area(b[:poly]), 1e-9
      assert_equal 350.0, b[:inner]
    end
  end

  def test_radius_resolution
    r = C.resolve_radius(400, 400, 25, 1.2, 50)
    assert_equal 50.0, r[:r]
    refute r[:changed]
    r = C.resolve_radius(400, 400, 25, 1.2, 10)
    assert r[:changed]
    assert_operator r[:r], :>, 25
    assert_match(/tự đổi R = #{Regexp.escape(C.fmt(r[:r]))}/, r[:messages].first)
    # R tối thiểu phải cho ra trải phẳng hợp lệ
    C.unfold_rounded(400, 400, 25, 1.2, r[:r], r[:n])
    r = C.resolve_radius(400, 300, 25, 1.2, 500)
    assert_equal 150.0, r[:r]
    assert r[:changed]
    assert_raises(ArgumentError) { C.resolve_radius(40, 40, 25, 1.2, 10) }
  end

  def test_path_closed_and_on_contour
    pts = C.rounded_rect_path(400, 400, 50, 12)
    assert_equal pts.first, pts.last
    pts.each { |x, y| assert_operator C.dist_to_rounded_rect(x, y, 400, 400, 50), :<, 1e-9 }
    xs = pts.map(&:first); ys = pts.map(&:last)
    assert_equal [0.0, 400.0], [xs.min, xs.max]
    assert_equal [0.0, 400.0], [ys.min, ys.max]
    assert_equal pts.size, C.dedupe(pts).size
    # R = nửa cạnh: không có đoạn thẳng, vẫn không trùng điểm
    circle = C.rounded_rect_path(400, 400, 200, 12)
    assert_equal circle.size, C.dedupe(circle).size
  end

  def test_unfold_miter
    p = C.unfold_miter(400, 400, 25, 1.2)
    assert_in_delta 1590.4, p[:length], 1e-9
    assert_equal 3, p[:notches].size
    d = 23.8
    p[:notches].each { |n| assert_in_delta d, n[:hw], 1e-9 }  # 45° mỗi bên
    assert_in_delta 1590.4 * 25 - 4 * d * d, p[:area], 1e-6
    assert_equal 1.2, p[:outline].map(&:last).reject(&:zero?).min
    p2 = C.unfold_miter(400, 400, 25, 2.0)
    assert_in_delta 1584.0, p2[:length], 1e-9
    assert_equal 2.0, p2[:outline].map(&:last).reject(&:zero?).min
  end

  def test_unfold_rounded
    p = C.unfold_rounded(400, 400, 25, 1.2, 50, 6)
    assert_in_delta 1200 + 2 * Math::PI * 48.8, p[:length], 1e-9
    assert_equal 24, p[:notches].size
    assert_in_delta 360.0, p[:notches].sum { |n| n[:angle] }, 1e-9
    assert_raises(ArgumentError) { C.unfold_rounded(400, 400, 25, 1.2, 26, 2) }
  end

  def test_default_back_is_wall_thickness
    info = { 'type' => 'miter', 'a' => 400.0, 'b' => 400.0, 'w' => 25.0, 't' => 1.4 }
    assert_equal 1.4, C.pattern_for(info)[:back]
    assert_equal 2.5, C.pattern_for(info, back: 2.5)[:back]
    assert_equal 1.4, C.pattern_for(info, back: 0)[:back]
  end

  def test_cut_plan_uses_developed_length_for_rounded
    rounded = { 'type' => 'rounded', 'a' => 400.0, 'b' => 400.0, 'w' => 25.0, 'h' => 25.0, 't' => 1.2,
                'r' => 50.0, 'n' => 6, 'back' => 1.2 }
    miter = { 'type' => 'miter', 'a' => 400.0, 'b' => 400.0, 'w' => 25.0, 'h' => 25.0, 't' => 1.2 }
    plan = DIYCatSat.cut_plan([rounded], stock: 6000, kerf: 2)
    assert_equal 1, plan[:bar_count]
    assert_in_delta 1200 + 2 * Math::PI * 48.8, plan[:bars][0][:pieces][0][:length], 1e-9
    plan = DIYCatSat.cut_plan([rounded], stock: 6000, kerf: 2, qty: 10)
    assert_equal 4, plan[:bar_count]
    plan = DIYCatSat.cut_plan([miter], qty: 3)
    assert_equal 1, plan[:bar_count]  # 12 x 400 + 12 x 2 = 4824
    plan = DIYCatSat.cut_plan([miter], qty: 4)
    assert_equal 2, plan[:bar_count]
    plan = DIYCatSat.cut_plan([miter], miter_mode: :one_piece)
    assert_in_delta 1590.4, plan[:bars][0][:pieces][0][:length], 1e-9
    plan[:bars].each { |b| assert_operator b[:waste], :>=, -1e-9 }
    assert_raises(ArgumentError) { C.optimize_cuts([{ label: 'x', length: 7000 }]) }
  end

  def test_optimizer_beats_naive
    pieces = [3100, 2900, 2900, 3100].map { |l| { label: 'p', length: l } }
    assert_equal 2, C.optimize_cuts(pieces, kerf: 0)[:bar_count]
  end

  def test_dxf_uses_input_back_and_correct_bevel
    miter = { 'type' => 'miter', 'a' => 400.0, 'b' => 400.0, 'w' => 25.0, 'h' => 25.0, 't' => 1.2,
              'profile' => '25x25x1.2' }
    Dir.mktmpdir do |d|
      [1.2, 2.0, 3.0].each do |back|
        path = File.join(d, "t#{back}.dxf")
        DIYCatSat.export_dxf(path, [miter], back: back, plan: DIYCatSat.cut_plan([miter]))
        txt = File.read(path)
        assert txt.end_with?("EOF\r\n")
        assert_includes txt, "LUNG=#{C.fmt(back)} "
        lines = txt.split("\r\n")
        khia = []
        lines.each_with_index do |l, i|
          next unless l == 'LINE' && lines[i + 2] == 'KHIA'
          v = lines[i + 3, 16].each_slice(2).to_h
          khia << [v['10'].to_f, v['20'].to_f, v['11'].to_f, v['21'].to_f]
        end
        assert_equal 3 * 2 + 2, khia.size
        khia.each do |x1, y1, x2, y2|
          assert_in_delta back, [y1, y2].min, 1e-4
          assert_in_delta 25.0, [y1, y2].max, 1e-4
          assert_in_delta (x1 - x2).abs, (y1 - y2).abs, 1e-4   # 45°
        end
        assert txt.ascii_only?
      end
    end
  end
end
