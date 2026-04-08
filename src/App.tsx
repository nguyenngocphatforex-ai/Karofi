/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Droplets, 
  ThermometerSnowflake, 
  ThermometerSun, 
  ShieldCheck, 
  Smartphone, 
  Zap, 
  CheckCircle2, 
  ChevronRight, 
  Menu, 
  X,
  ArrowRight,
  Waves,
  Info,
  Award
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

// Utility for tailwind classes
function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// --- Components ---

const Navbar = ({ onBuyNow }: { onBuyNow: () => void }) => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const navLinks = [
    { name: 'Tính năng', href: '#features' },
    { name: 'Công nghệ', href: '#tech' },
    { name: 'Thiết kế', href: '#design' },
    { name: 'Thông số', href: '#specs' },
  ];

  return (
    <nav className={cn(
      "fixed top-0 left-0 right-0 z-50 transition-all duration-300 px-6 py-4",
      isScrolled ? "bg-white/80 backdrop-blur-md shadow-sm py-3" : "bg-transparent"
    )}>
      <div className="max-w-7xl mx-auto flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center text-white font-bold text-xl">
            K
          </div>
          <span className={cn(
            "font-bold text-xl tracking-tighter",
            isScrolled ? "text-slate-900" : "text-slate-900"
          )}>
            KAROFI <span className="font-light text-blue-500">PLATINUM</span>
          </span>
        </div>

        {/* Desktop Nav */}
        <div className="hidden md:flex items-center gap-8">
          {navLinks.map((link) => (
            <a 
              key={link.name} 
              href={link.href}
              className="text-sm font-medium text-slate-600 hover:text-blue-600 transition-colors"
            >
              {link.name}
            </a>
          ))}
          <button 
            onClick={onBuyNow}
            className="bg-blue-600 text-white px-5 py-2 rounded-full text-sm font-semibold hover:bg-blue-700 transition-all shadow-lg shadow-blue-200"
          >
            Mua ngay
          </button>
        </div>

        {/* Mobile Toggle */}
        <button 
          className="md:hidden p-2 text-slate-900"
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
        >
          {mobileMenuOpen ? <X /> : <Menu />}
        </button>
      </div>

      {/* Mobile Menu */}
      <AnimatePresence>
        {mobileMenuOpen && (
          <motion.div 
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="absolute top-full left-0 right-0 bg-white border-t border-slate-100 p-6 flex flex-col gap-4 md:hidden shadow-xl"
          >
            {navLinks.map((link) => (
              <a 
                key={link.name} 
                href={link.href}
                className="text-lg font-medium text-slate-600"
                onClick={() => setMobileMenuOpen(false)}
              >
                {link.name}
              </a>
            ))}
            <button 
              onClick={() => {
                setMobileMenuOpen(false);
                onBuyNow();
              }}
              className="bg-blue-600 text-white py-3 rounded-xl font-semibold"
            >
              Mua ngay
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};

const FeatureCard = ({ icon: Icon, title, description, delay = 0 }: { icon: any, title: string, description: string, delay?: number }) => (
  <motion.div 
    initial={{ opacity: 0, y: 20 }}
    whileInView={{ opacity: 1, y: 0 }}
    viewport={{ once: true }}
    transition={{ delay }}
    className="bg-white p-8 rounded-3xl border border-slate-100 shadow-sm hover:shadow-xl transition-all group"
  >
    <div className="w-14 h-14 bg-blue-50 rounded-2xl flex items-center justify-center text-blue-600 mb-6 group-hover:bg-blue-600 group-hover:text-white transition-colors">
      <Icon size={28} />
    </div>
    <h3 className="text-xl font-bold text-slate-900 mb-3">{title}</h3>
    <p className="text-slate-500 leading-relaxed">{description}</p>
  </motion.div>
);

const SpecRow = ({ label, value }: { label: string, value: string }) => (
  <div className="flex justify-between py-4 border-bottom border-slate-100">
    <span className="text-slate-500 font-medium">{label}</span>
    <span className="text-slate-900 font-semibold text-right">{value}</span>
  </div>
);

const CheckoutModal = ({ isOpen, onClose }: { isOpen: boolean, onClose: () => void }) => {
  const [step, setStep] = useState(1);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    address: ''
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    
    const SCRIPT_URL = import.meta.env.VITE_GOOGLE_SCRIPT_URL;
    
    try {
      if (SCRIPT_URL) {
        // We use 'no-cors' mode for simple Apps Script integration
        await fetch(SCRIPT_URL, {
          method: 'POST',
          mode: 'no-cors',
          cache: 'no-cache',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(formData),
        });
      } else {
        console.warn('VITE_GOOGLE_SCRIPT_URL is not defined. Data not sent to Google Sheets.');
      }
      setStep(2);
    } catch (error) {
      console.error('Error submitting form:', error);
      // Still move to step 2 for user experience, or you could show an error
      setStep(2);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm"
          />
          <motion.div 
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
            className="relative bg-white w-full max-w-lg rounded-[32px] overflow-hidden shadow-2xl"
          >
            <button 
              onClick={onClose}
              className="absolute top-6 right-6 p-2 text-slate-400 hover:text-slate-900 transition-colors z-10"
            >
              <X size={24} />
            </button>

            <div className="p-8 md:p-12">
              {step === 1 ? (
                <>
                  <div className="mb-8">
                    <h3 className="text-3xl font-bold text-slate-900 mb-2">Đặt hàng ngay</h3>
                    <p className="text-slate-500">Vui lòng điền thông tin để chúng tôi liên hệ tư vấn và giao hàng.</p>
                  </div>

                  <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                      <label className="block text-sm font-bold text-slate-700 mb-2 uppercase tracking-wider">Họ và tên</label>
                      <input 
                        required
                        type="text" 
                        placeholder="Nguyễn Văn A"
                        className="w-full bg-slate-50 border border-slate-100 rounded-2xl px-6 py-4 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-all"
                        value={formData.name}
                        onChange={(e) => setFormData({...formData, name: e.target.value})}
                      />
                    </div>
                    <div className="grid md:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-bold text-slate-700 mb-2 uppercase tracking-wider">Email</label>
                        <input 
                          required
                          type="email" 
                          placeholder="example@gmail.com"
                          className="w-full bg-slate-50 border border-slate-100 rounded-2xl px-6 py-4 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-all"
                          value={formData.email}
                          onChange={(e) => setFormData({...formData, email: e.target.value})}
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-bold text-slate-700 mb-2 uppercase tracking-wider">Số điện thoại</label>
                        <input 
                          required
                          type="tel" 
                          placeholder="09xx xxx xxx"
                          className="w-full bg-slate-50 border border-slate-100 rounded-2xl px-6 py-4 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-all"
                          value={formData.phone}
                          onChange={(e) => setFormData({...formData, phone: e.target.value})}
                        />
                      </div>
                    </div>
                    <div>
                      <label className="block text-sm font-bold text-slate-700 mb-2 uppercase tracking-wider">Địa chỉ đặt hàng</label>
                      <textarea 
                        required
                        placeholder="Số nhà, tên đường, phường/xã..."
                        rows={3}
                        className="w-full bg-slate-50 border border-slate-100 rounded-2xl px-6 py-4 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-all resize-none"
                        value={formData.address}
                        onChange={(e) => setFormData({...formData, address: e.target.value})}
                      />
                    </div>
                    <button 
                      type="submit"
                      disabled={isSubmitting}
                      className={cn(
                        "w-full bg-blue-600 text-white py-5 rounded-2xl font-bold text-xl hover:bg-blue-700 transition-all shadow-xl shadow-blue-200 mt-4 flex items-center justify-center gap-3",
                        isSubmitting && "opacity-70 cursor-not-allowed"
                      )}
                    >
                      {isSubmitting ? (
                        <>
                          <div className="w-6 h-6 border-4 border-white/30 border-t-white rounded-full animate-spin" />
                          Đang xử lý...
                        </>
                      ) : "Tiếp tục thanh toán"}
                    </button>
                  </form>
                </>
              ) : (
                <div className="text-center py-4">
                  <div className="w-20 h-20 bg-green-100 text-green-600 rounded-full flex items-center justify-center mx-auto mb-6">
                    <CheckCircle2 size={40} />
                  </div>
                  <h3 className="text-3xl font-bold text-slate-900 mb-4">Xác nhận đơn hàng</h3>
                  <div className="bg-slate-50 rounded-3xl p-6 mb-8 text-left">
                    <div className="flex justify-between mb-4 pb-4 border-b border-slate-200">
                      <span className="text-slate-500">Sản phẩm</span>
                      <span className="font-bold">Karofi Platinum S6</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-slate-500">Tổng thanh toán</span>
                      <span className="text-2xl font-black text-blue-600">21.990.000 VNĐ</span>
                    </div>
                  </div>
                  <p className="text-slate-500 mb-8">
                    Cảm ơn <strong>{formData.name}</strong>! Nhân viên Karofi sẽ liên hệ với bạn qua số điện thoại <strong>{formData.phone}</strong> trong vòng 15 phút để hoàn tất thanh toán.
                  </p>
                  <button 
                    onClick={onClose}
                    className="w-full bg-slate-900 text-white py-5 rounded-2xl font-bold text-xl hover:bg-slate-800 transition-all"
                  >
                    Đóng
                  </button>
                </div>
              )}
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};

export default function App() {
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false);

  return (
    <div className="min-h-screen bg-white font-sans text-slate-900 selection:bg-blue-100 selection:text-blue-900">
      <Navbar onBuyNow={() => setIsCheckoutOpen(true)} />

      {/* Hero Section */}
      <section className="relative pt-32 pb-20 lg:pt-48 lg:pb-32 overflow-hidden">
        <div className="absolute top-0 right-0 -z-10 w-1/2 h-full bg-slate-50 rounded-l-[100px] hidden lg:block" />
        <div className="max-w-7xl mx-auto px-6 grid lg:grid-cols-2 gap-12 items-center">
          <motion.div
            initial={{ opacity: 0, x: -50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.8 }}
          >
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-blue-50 text-blue-600 text-xs font-bold uppercase tracking-wider mb-6">
              <Award size={14} />
              Sản phẩm cao cấp 2024
            </div>
            <h1 className="text-5xl lg:text-7xl font-bold tracking-tight text-slate-900 mb-6 leading-[1.1]">
              Karofi Platinum <span className="text-blue-600">S6</span>
              <br />
              <span className="text-slate-400 font-light">Đỉnh cao tinh khiết</span>
            </h1>
            <p className="text-xl text-slate-500 mb-10 max-w-lg leading-relaxed">
              Trải nghiệm sự tiện nghi hoàn hảo với 3 chế độ nước Nóng - Lạnh - Nguội, công nghệ AioTec thông minh và thiết kế Platinum sang trọng.
            </p>
            <div className="flex flex-wrap gap-4">
              <button 
                onClick={() => setIsCheckoutOpen(true)}
                className="bg-blue-600 text-white px-8 py-4 rounded-2xl font-bold text-lg hover:bg-blue-700 transition-all shadow-xl shadow-blue-200 flex items-center gap-2 group"
              >
                Mua ngay
                <ArrowRight className="group-hover:translate-x-1 transition-transform" />
              </button>
            </div>
            
            <div className="mt-12 flex items-center gap-8">
              <div className="flex -space-x-3">
                {[1, 2, 3, 4].map((i) => (
                  <div key={i} className="w-10 h-10 rounded-full border-2 border-white bg-slate-200 overflow-hidden">
                    <img src={`https://picsum.photos/seed/user${i}/100/100`} alt="User" referrerPolicy="no-referrer" />
                  </div>
                ))}
              </div>
              <div className="text-sm font-medium text-slate-500">
                <span className="text-slate-900 font-bold">10,000+</span> gia đình tin dùng
              </div>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1, delay: 0.2 }}
            className="relative"
          >
            <div className="absolute inset-0 bg-blue-400/10 blur-[120px] rounded-full -z-10" />
            <img 
              src="https://karofi.karofi.com/karofi-com/2026/01/karofi-platinum-s6-1.png" 
              alt="Karofi Platinum S6" 
              className="w-full h-auto drop-shadow-[0_35px_35px_rgba(0,0,0,0.15)]"
              referrerPolicy="no-referrer"
              onError={(e) => {
                // Fallback if image fails
                (e.target as HTMLImageElement).src = "https://picsum.photos/seed/water-purifier/600/800";
              }}
            />
            
            {/* Floating Badges */}
            <motion.div 
              animate={{ y: [0, -10, 0] }}
              transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
              className="absolute top-1/4 -left-8 bg-white p-4 rounded-2xl shadow-xl border border-slate-100 flex items-center gap-3"
            >
              <div className="w-10 h-10 bg-orange-100 text-orange-600 rounded-xl flex items-center justify-center">
                <ThermometerSun size={20} />
              </div>
              <div>
                <div className="text-[10px] font-bold text-slate-400 uppercase">Nước nóng</div>
                <div className="text-sm font-bold">Lên đến 95°C</div>
              </div>
            </motion.div>

            <motion.div 
              animate={{ y: [0, 10, 0] }}
              transition={{ duration: 5, repeat: Infinity, ease: "easeInOut", delay: 1 }}
              className="absolute bottom-1/4 -right-8 bg-white p-4 rounded-2xl shadow-xl border border-slate-100 flex items-center gap-3"
            >
              <div className="w-10 h-10 bg-blue-100 text-blue-600 rounded-xl flex items-center justify-center">
                <ThermometerSnowflake size={20} />
              </div>
              <div>
                <div className="text-[10px] font-bold text-slate-400 uppercase">Nước lạnh</div>
                <div className="text-sm font-bold">Sâu đến 6°C</div>
              </div>
            </motion.div>
          </motion.div>
        </div>
      </section>

      {/* Features Grid */}
      <section id="features" className="py-24 bg-slate-50">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center max-w-3xl mx-auto mb-20">
            <h2 className="text-3xl lg:text-5xl font-bold mb-6">Tính năng vượt trội</h2>
            <p className="text-lg text-slate-500">
              Karofi Platinum S6 không chỉ là một máy lọc nước, mà là một quản gia thông minh chăm sóc sức khỏe cho cả gia đình bạn.
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <FeatureCard 
              icon={ThermometerSun}
              title="3 Chế độ nước tiện lợi"
              description="Cung cấp nước Nóng - Lạnh - Nguội tức thì, đáp ứng mọi nhu cầu từ pha trà, cafe đến giải khát ngày hè."
              delay={0.1}
            />
            <FeatureCard 
              icon={Smartphone}
              title="Công nghệ AioTec"
              description="Giám sát chất lượng nước từ xa qua ứng dụng Karofi 360. Cảnh báo thay lõi, rò rỉ nước thông minh."
              delay={0.2}
            />
            <FeatureCard 
              icon={ShieldCheck}
              title="Hệ thống 10 lõi Smax"
              description="Gấp đôi công suất lọc, nhân đôi tuổi thọ lõi. Loại bỏ 99.99% tạp chất, vi khuẩn và kim loại nặng."
              delay={0.3}
            />
            <FeatureCard 
              icon={Waves}
              title="Nước giàu Hydrogen"
              description="Bổ sung Hydrogen chống oxy hóa, hỗ trợ tăng cường sức đề kháng và làm đẹp da từ bên trong."
              delay={0.4}
            />
            <FeatureCard 
              icon={Zap}
              title="Tiết kiệm điện năng"
              description="Công nghệ bảo ôn đa lớp giúp giữ nhiệt lâu hơn, giảm thiểu tiêu thụ điện năng lên đến 30%."
              delay={0.5}
            />
            <FeatureCard 
              icon={CheckCircle2}
              title="Chuẩn quốc gia QCVN6-1"
              description="Nước sau lọc đạt chuẩn nước uống trực tiếp đóng chai của Bộ Y Tế, an toàn tuyệt đối."
              delay={0.6}
            />
          </div>
        </div>
      </section>

      {/* Technology Section */}
      <section id="tech" className="py-24 overflow-hidden">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid lg:grid-cols-2 gap-20 items-center">
            <motion.div
              initial={{ opacity: 0, x: -50 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              className="relative"
            >
              <div className="aspect-square bg-blue-600 rounded-[60px] overflow-hidden relative">
                <img 
                  src="https://picsum.photos/seed/filtration/800/800" 
                  alt="Smax Technology" 
                  className="w-full h-full object-cover mix-blend-overlay opacity-50"
                  referrerPolicy="no-referrer"
                />
                <div className="absolute inset-0 flex flex-col justify-end p-12 text-white">
                  <h3 className="text-4xl font-bold mb-4">Công nghệ Smax Pro</h3>
                  <p className="text-blue-100 text-lg">
                    Đột phá trong thiết kế lõi lọc, tăng diện tích tiếp xúc, tối ưu hóa dòng chảy và hiệu suất lọc vượt trội.
                  </p>
                </div>
              </div>
              {/* Decorative elements */}
              <div className="absolute -top-6 -right-6 w-32 h-32 border-4 border-blue-100 rounded-full -z-10" />
              <div className="absolute -bottom-10 -left-10 w-48 h-48 bg-blue-50 rounded-full -z-10" />
            </motion.div>

            <div>
              <h2 className="text-4xl font-bold mb-8 leading-tight">Hệ thống lọc 10 lõi mạnh mẽ</h2>
              <div className="space-y-8">
                {[
                  { title: "Cụm lõi lọc thô Smax Pro V", desc: "Loại bỏ tạp chất, cặn bẩn kích thước lớn, bảo vệ màng RO." },
                  { title: "Màng RO Purifim Mỹ", desc: "Trái tim của máy, loại bỏ 99.99% vi khuẩn, virus, ion kim loại nặng." },
                  { title: "Cụm lõi chức năng Smax hiệu suất cao", desc: "Bổ sung khoáng chất, Hydrogen, cân bằng pH và tạo vị ngọt cho nước." }
                ].map((item, i) => (
                  <motion.div 
                    key={i}
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    viewport={{ once: true }}
                    transition={{ delay: i * 0.1 }}
                    className="flex gap-6"
                  >
                    <div className="flex-shrink-0 w-12 h-12 rounded-full bg-blue-600 text-white flex items-center justify-center font-bold">
                      {i + 1}
                    </div>
                    <div>
                      <h4 className="text-xl font-bold mb-2">{item.title}</h4>
                      <p className="text-slate-500 leading-relaxed">{item.desc}</p>
                    </div>
                  </motion.div>
                ))}
              </div>
              <button 
                onClick={() => setIsCheckoutOpen(true)}
                className="mt-12 text-blue-600 font-bold flex items-center gap-2 hover:gap-3 transition-all"
              >
                Mua ngay <ChevronRight size={20} />
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Design Section */}
      <section id="design" className="py-24 bg-slate-900 text-white">
        <div className="max-w-7xl mx-auto px-6 text-center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
          >
            <h2 className="text-4xl lg:text-6xl font-bold mb-8">Thiết kế Platinum thời thượng</h2>
            <p className="text-xl text-slate-400 max-w-3xl mx-auto mb-16">
              Vẻ đẹp tinh tế từ chất liệu cao cấp, màu sắc trang nhã, Platinum S6 là điểm nhấn hoàn hảo cho không gian sống hiện đại.
            </p>
          </motion.div>

          <div className="grid lg:grid-cols-3 gap-8">
            <div className="relative group overflow-hidden rounded-[40px]">
              <img src="https://picsum.photos/seed/kitchen1/600/800" alt="Kitchen" className="w-full aspect-[3/4] object-cover transition-transform duration-700 group-hover:scale-110" referrerPolicy="no-referrer" />
              <div className="absolute inset-0 bg-gradient-to-t from-slate-900 via-transparent to-transparent flex flex-col justify-end p-8 text-left">
                <h4 className="text-xl font-bold">Phòng bếp hiện đại</h4>
                <p className="text-slate-400 text-sm">Tối ưu không gian, tiện nghi tối đa</p>
              </div>
            </div>
            <div className="relative group overflow-hidden rounded-[40px] lg:translate-y-12">
              <img src="https://picsum.photos/seed/livingroom/600/800" alt="Living Room" className="w-full aspect-[3/4] object-cover transition-transform duration-700 group-hover:scale-110" referrerPolicy="no-referrer" />
              <div className="absolute inset-0 bg-gradient-to-t from-slate-900 via-transparent to-transparent flex flex-col justify-end p-8 text-left">
                <h4 className="text-xl font-bold">Phòng khách sang trọng</h4>
                <p className="text-slate-400 text-sm">Điểm nhấn thẩm mỹ đẳng cấp</p>
              </div>
            </div>
            <div className="relative group overflow-hidden rounded-[40px]">
              <img src="https://picsum.photos/seed/office/600/800" alt="Office" className="w-full aspect-[3/4] object-cover transition-transform duration-700 group-hover:scale-110" referrerPolicy="no-referrer" />
              <div className="absolute inset-0 bg-gradient-to-t from-slate-900 via-transparent to-transparent flex flex-col justify-end p-8 text-left">
                <h4 className="text-xl font-bold">Văn phòng chuyên nghiệp</h4>
                <p className="text-slate-400 text-sm">Năng lượng cho ngày làm việc</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Specifications Section */}
      <section id="specs" className="py-24">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid lg:grid-cols-2 gap-16 items-start">
            <div>
              <h2 className="text-4xl font-bold mb-8">Thông số kỹ thuật</h2>
              <div className="bg-slate-50 p-8 rounded-[40px]">
                <SpecRow label="Số lõi lọc" value="10 lõi" />
                <SpecRow label="Chế độ nước" value="Nóng - Lạnh - Nguội" />
                <SpecRow label="Công suất lọc" value="20 L/h" />
                <SpecRow label="Dung tích bình nóng" value="1 L" />
                <SpecRow label="Dung tích bình lạnh" value="1 L" />
                <SpecRow label="Nhiệt độ nước nóng" value="85 - 95°C" />
                <SpecRow label="Nhiệt độ nước lạnh" value="6 - 10°C" />
                <SpecRow label="Kích thước (RxSxC)" value="320 x 400 x 990 mm" />
                <SpecRow label="Khối lượng" value="32 kg" />
                <SpecRow label="Bảo hành" value="36 tháng" />
              </div>
            </div>
            <div className="lg:sticky lg:top-32">
              <div className="bg-blue-600 rounded-[40px] p-12 text-white relative overflow-hidden">
                <div className="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full -translate-y-1/2 translate-x-1/2 blur-3xl" />
                <h3 className="text-3xl font-bold mb-2">Ưu đãi đặc biệt</h3>
                <div className="text-4xl font-black mb-6 text-white">21.990.000 VNĐ</div>
                <p className="text-blue-100 text-lg mb-8">
                  Đặt mua ngay hôm nay để nhận bộ quà tặng trị giá <span className="text-white font-bold">2.000.000đ</span> và miễn phí lắp đặt toàn quốc.
                </p>
                <div className="space-y-4 mb-10">
                  <div className="flex items-center gap-3">
                    <CheckCircle2 className="text-blue-300" />
                    <span>Tặng bộ 3 lõi lọc thô Smax Pro V</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <CheckCircle2 className="text-blue-300" />
                    <span>Tặng bút thử nước TDS cao cấp</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <CheckCircle2 className="text-blue-300" />
                    <span>Miễn phí bảo trì định kỳ 1 năm</span>
                  </div>
                </div>
                <button 
                  onClick={() => setIsCheckoutOpen(true)}
                  className="w-full bg-white text-blue-600 py-4 rounded-2xl font-bold text-xl hover:bg-blue-50 transition-all shadow-xl"
                >
                  Mua ngay
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section className="py-24 bg-slate-50">
        <div className="max-w-3xl mx-auto px-6">
          <h2 className="text-3xl font-bold text-center mb-12">Câu hỏi thường gặp</h2>
          <div className="space-y-6">
            {[
              { q: "Máy có tốn điện không?", a: "Nhờ công nghệ bảo ôn đa lớp và hệ thống làm lạnh bằng Block, máy cực kỳ tiết kiệm điện, chỉ tương đương một chiếc bóng đèn sợi đốt khi ở chế độ chờ." },
              { q: "Bao lâu thì cần thay lõi lọc?", a: "Lõi lọc thô từ 6-12 tháng, màng RO từ 24-36 tháng, lõi chức năng từ 12 tháng. Ứng dụng AioTec sẽ thông báo chính xác thời điểm cần thay cho bạn." },
              { q: "Nước có uống trực tiếp được không?", a: "Hoàn toàn được. Nước sau lọc đạt chuẩn QCVN6-1 của Bộ Y Tế, cao nhất dành cho nước uống trực tiếp." }
            ].map((faq, i) => (
              <div key={i} className="bg-white p-6 rounded-2xl shadow-sm border border-slate-100">
                <h4 className="font-bold text-lg mb-2 flex items-center gap-2">
                  <Info size={18} className="text-blue-600" />
                  {faq.q}
                </h4>
                <p className="text-slate-500">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-slate-900 text-slate-400 py-20">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-12 mb-16">
            <div className="col-span-1 lg:col-span-1">
              <div className="flex items-center gap-2 mb-6">
                <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                  K
                </div>
                <span className="font-bold text-xl tracking-tighter text-white">
                  KAROFI
                </span>
              </div>
              <p className="text-sm leading-relaxed mb-6">
                Tập đoàn Karofi - Chuyên gia lọc nước thông minh hàng đầu Việt Nam. Mang nguồn nước tinh khiết đến mọi gia đình.
              </p>
              <div className="flex gap-4">
                {[1, 2, 3, 4].map(i => (
                  <div key={i} className="w-10 h-10 rounded-full bg-slate-800 flex items-center justify-center hover:bg-blue-600 hover:text-white transition-colors cursor-pointer">
                    <Zap size={18} />
                  </div>
                ))}
              </div>
            </div>
            
            <div>
              <h4 className="text-white font-bold mb-6">Sản phẩm</h4>
              <ul className="space-y-4 text-sm">
                <li><a href="#" className="hover:text-white transition-colors">Máy lọc nước RO</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Máy lọc nước Nóng Lạnh</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Máy lọc nước Hydrogen</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Linh phụ kiện</a></li>
              </ul>
            </div>

            <div>
              <h4 className="text-white font-bold mb-6">Hỗ trợ</h4>
              <ul className="space-y-4 text-sm">
                <li><a href="#" className="hover:text-white transition-colors">Trung tâm bảo hành</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Kích hoạt bảo hành</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Hướng dẫn sử dụng</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Chính sách đổi trả</a></li>
              </ul>
            </div>

            <div>
              <h4 className="text-white font-bold mb-6">Liên hệ</h4>
              <ul className="space-y-4 text-sm">
                <li className="flex items-start gap-3">
                  <Info size={18} className="text-blue-600 flex-shrink-0" />
                  <span>Tầng 11, Tòa nhà HUD Tower, Số 37 Lê Văn Lương, Thanh Xuân, Hà Nội</span>
                </li>
                <li className="flex items-center gap-3">
                  <Smartphone size={18} className="text-blue-600 flex-shrink-0" />
                  <span>Hotline: 1900 6418</span>
                </li>
                <li className="flex items-center gap-3">
                  <Zap size={18} className="text-blue-600 flex-shrink-0" />
                  <span>Email: info@karofi.com</span>
                </li>
              </ul>
            </div>
          </div>
          
          <div className="pt-8 border-t border-slate-800 flex flex-col md:flex-row justify-between items-center gap-4 text-xs">
            <p>© 2024 Karofi Group. All rights reserved.</p>
            <div className="flex gap-8">
              <a href="#" className="hover:text-white transition-colors">Điều khoản sử dụng</a>
              <a href="#" className="hover:text-white transition-colors">Chính sách bảo mật</a>
            </div>
          </div>
        </div>
      </footer>
      <CheckoutModal isOpen={isCheckoutOpen} onClose={() => setIsCheckoutOpen(false)} />
    </div>
  );
}
