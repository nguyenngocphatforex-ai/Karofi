# encoding: UTF-8
# Giả lập TỐI THIỂU API SketchUp để chạy thử luồng code của Build/test.rb trên
# máy không có SketchUp (bắt lỗi gõ tên hàm, sai tham số...). KHÔNG mô phỏng
# hình học thật: followme chỉ là giả, nên các phép đo khung bo góc sẽ sai.
#   ruby dev_tests/mock_sketchup.rb
INCH = 25.4
class Numeric
  def mm; to_f / INCH; end
  def to_mm; to_f * INCH; end
end

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def to_a; [x, y, z]; end
    def ==(o); o.is_a?(Point3d) && to_a.zip(o.to_a).all? { |a, b| (a - b).abs < 1e-9 }; end
  end
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def angle_between(o)
      d = (x * o.x + y * o.y + z * o.z) / (Math.sqrt(x**2 + y**2 + z**2) * Math.sqrt(o.x**2 + o.y**2 + o.z**2))
      Math.acos([[d, 1].min, -1].max)
    end
  end
  class Transformation
    attr_reader :origin
    def initialize(o = Point3d.new); @origin = o; end
    def self.translation(v); new(Point3d.new(v.x, v.y, v.z)); end
  end
  class BoundingBox
    def initialize; @pts = []; end
    def add(*ps); @pts.concat(ps.flatten); self; end
    def empty?; @pts.empty?; end
    def min; Point3d.new(*(0..2).map { |i| @pts.map { |p| p.to_a[i] }.min }); end
    def max; Point3d.new(*(0..2).map { |i| @pts.map { |p| p.to_a[i] }.max }); end
    def width; empty? ? 0.0 : max.x - min.x; end
    def height; empty? ? 0.0 : max.y - min.y; end
    def depth; empty? ? 0.0 : max.z - min.z; end
  end
end

module Sketchup
  def self.version; 'MOCK'; end
  def self.quit; end
  @model = nil
  def self.active_model; @model ||= Model.new; end

  class Entity
    def valid?; !@erased; end
    def erase!; @erased = true; @parent&.remove(self); end
    attr_accessor :parent
    def attribute_dictionary(n); (@dicts ||= {})[n] && AttributeDictionary.new((@dicts ||= {})[n]); end
    def set_attribute(d, k, v); ((@dicts ||= {})[d] ||= {})[k] = v; end
    def get_attribute(d, k, default = nil); ((@dicts ||= {})[d] || {}).fetch(k, default); end
  end
  class AttributeDictionary
    include Enumerable
    def initialize(h); @h = h; end
    def each_pair(&b); @h.each_pair(&b); end
    def each(&b); @h.each(&b); end
  end
  class Vertex
    attr_reader :position
    def initialize(p); @position = p; end
  end
  class Edge < Entity
    attr_accessor :soft, :smooth
    attr_reader :start, :end
    def initialize(a, b); @start = Vertex.new(a); @end = Vertex.new(b); @faces = []; end
    def faces; @faces.select(&:valid?); end
    def add_face(f); @faces << f; end
    def length; p = @start.position; q = @end.position; Math.sqrt((p.x - q.x)**2 + (p.y - q.y)**2 + (p.z - q.z)**2); end
  end
  class Loop
    def initialize(pts); @pts = pts; end
  end
  class Face < Entity
    attr_reader :pts, :edges, :loops
    def initialize(ents, pts)
      @ents = ents; @pts = pts; @edges = []; @loops = [Loop.new(pts)]; @normal_sign = 1.0
    end
    def plane_normal
      n = [0.0, 0.0, 0.0]
      @pts.each_with_index do |p, i|
        q = @pts[(i + 1) % @pts.size]
        n[0] += (p.y - q.y) * (p.z + q.z); n[1] += (p.z - q.z) * (p.x + q.x); n[2] += (p.x - q.x) * (p.y + q.y)
      end
      n
    end
    def normal; n = plane_normal; Geom::Vector3d.new(*n.map { |v| v * @normal_sign }); end
    def reverse!; @normal_sign = -@normal_sign; self; end
    def area; n = plane_normal; Math.sqrt(n.sum { |v| v * v }) / 2.0; end
    def add_hole(pts); @loops << Loop.new(pts); end
    def pushpull(dist)
      nz = normal.z.positive? ? 1.0 : -1.0
      top = @pts.map { |p| Geom::Point3d.new(p.x, p.y, p.z + nz * dist) }
      @ents.add_face(top)
      @pts.each_with_index do |p, i|
        q = @pts[(i + 1) % @pts.size]
        @ents.add_face([p, q, top[(i + 1) % top.size], top[i]])
      end
      @ents.solid_volume += area * dist.abs
      true
    end
    def followme(path)
      raise ArgumentError, 'path' unless path.is_a?(Array) && path.all? { |e| e.is_a?(Edge) }
      true
    end
  end
  class Group < Entity
    attr_accessor :name
    attr_reader :entities, :transformation
    def initialize; @entities = Entities.new; @transformation = Geom::Transformation.new; end
    def transform!(t)
      @transformation = t
      @entities.shift!(t.origin)
      self
    end
    def bounds; @entities.bounds; end
    def manifold?; @entities.solid_volume > 0; end
    def volume; @entities.solid_volume; end
  end
  class Entities
    include Enumerable
    attr_accessor :solid_volume
    def initialize; @list = []; @solid_volume = 0.0; @offset = Geom::Point3d.new; end
    def each(&b); @list.each(&b); end
    def to_a; @list.dup; end
    def remove(e); @list.delete(e); end
    def clear!; @list.clear; end
    def <<(e); e.parent = self; @list << e; e; end
    def add_group; self << Group.new; end
    def add_edges(pts)
      pts.each_cons(2).map { |a, b| self << Edge.new(a, b) }
    end
    def add_line(a, b); self << Edge.new(a, b); end
    def add_face(pts)
      pts = pts.flatten
      host = @list.grep(Face).find { |f| f.valid? && pts.all? { |p| p.x == f.pts[0].x } && f.pts[0].x == pts[0].x } if pts.all? { |p| p.x == pts[0].x }
      f = Face.new(self, pts)
      host&.add_hole(pts)
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        e = @list.grep(Edge).find { |x| (x.start.position == p && x.end.position == q) || (x.start.position == q && x.end.position == p) }
        e ||= (self << Edge.new(p, q))
        e.add_face(f)
        f.edges << e
      end
      self << f
    end
    def shift!(o)
      @offset = o
    end
    # bao trong toạ độ cha (cộng offset của group)
    def bounds
      bb = Geom::BoundingBox.new
      @list.each do |e|
        ps = case e
             when Face then e.pts
             when Edge then [e.start.position, e.end.position]
             when Group then (b = e.bounds).empty? ? [] : [b.min, b.max]
             else []
             end
        bb.add(ps.map { |p| Geom::Point3d.new(p.x + @offset.x, p.y + @offset.y, p.z + @offset.z) })
      end
      bb
    end
  end
  class Selection
    def to_a; []; end
  end
  class Model
    def start_operation(*); end
    def commit_operation; end
    def abort_operation; end
    def active_entities; @ents ||= Entities.new; end
    def entities; active_entities; end
    def bounds; active_entities.bounds; end
    def selection; Selection.new; end
  end
end

module UI
  def self.start_timer(_s, _r = false); yield; end
  def self.messagebox(m); puts "[messagebox] #{m}"; end
  def self.menu(_n); Menu.new; end
  class Menu
    def add_submenu(_n); self; end
    def add_item(_n); end
  end
end

def file_loaded?(_f); false; end
def file_loaded(_f); end

require 'tmpdir'
dir = Dir.mktmpdir('diy_mock')
src = File.expand_path('..', __dir__)
%w[diy_cat_sat.rb test.rb].each { |f| FileUtils.cp(File.join(src, f), dir) }
ENV['APPDATA'] = File.join(dir, 'AppData')
load File.join(dir, 'test.rb')
puts "\n===== log.txt (mock) =====\n"
puts File.read(File.join(dir, 'log.txt'))
