require 'pathname'      #pathname modülünü kullan
require 'pythonconfig'      #pythonconfig modülünü kullan
require 'yaml'      #yaml modülünü kullan

CONFIG = Config.fetch('presentation', {})       #presantation'ı al yoksa sözlük al

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')       #director'i al yoksa p'yi al
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')      #DEFAULT CONFFILE'a conffile al yoksa presentation.cfg dosyasını al
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')      #PRESENTATION_DIR'ı index.html ile birleştir INDEX_FILE'al
IMAGE_GEOMETRY = [ 733, 550 ]       #resim boyutları en fazla (733,550) 
DEPEND_KEYS    = %w(source css js)      #["source", "css", "js"]şeklinde listele
DEPEND_ALWAYS  = %w(media)      #["media"] şeklinde 
TASKS = {       #görev çiftleri task içinde
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {}     #sunum bilgilerini içeren sözlük
tag            = {}     #etiket bilgilerini içeren sözlük

class File      #File sınıfı oluştur
  @@absolute_path_here = Pathname.new(Pathname.pwd)     #dosya yolunu bir değişkene ata
  def self.to_herepath(path)        
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s      #yeni bir yol oluştur
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)
  require 'chunky_png'      #chunky_png modülünü kullan
  require 'oily_png'        #oily_png modülünü kullan

  image = ChunkyPNG::Image.from_file(file)      #resmi al
  image.metadata['Comment'] = 'raked'       #resmi güncelle
  image.save(file)      #resmi kaydet
end

def png_optim(file, threshold=40000)        #png uzantılı resimleri 40000 eşik değerine göre optimize et
  return if File.new(file).size < threshold     #eşik değerden küçükse geri dön
  sh "pngnq -f -e .png-nq #{file}"      #değilse optimize et
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)     #isim çakışması olursa gider
  end
  png_comment(file, 'raked')        #resmin işlendiğini belirt
end

def jpg_optim(file)     #jpg uzantılı resimleri optimize et
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]      #png uzantılı dosyaları pngs olarak,jpg jpeg uzantılı dosyaları jpgs olarak listele

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }      #optimize edilmemiş resimleri al
  end

  (pngs + jpgs).each do |f|     
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }     #genişliği w,yüksekliği h değişkenine ata
    size, i = [w, h].each_with_index.max        #w,h 'yi size ata
    if size > IMAGE_GEOMETRY[i]     #size IMAGE_GEOMETRY den büyükse
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s     #optimize et
      sh "mogrify -resize #{arg} #{f}"      #ve bildir
    end
  end

  pngs.each { |f| png_optim(f) }        #png uzantılı resimler için
  jpgs.each { |f| jpg_optim(f) }        #jpg veya jpeg uzantılı resimler için 

  (pngs + jpgs).each do |f|     #pngs ve jpgs'den gelen resimleri al
    name = File.basename f
    FileList["*/*.md"].each do |src|        #.md uzantılı dosyalarda varsa
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"     #ekrana basmadan dosyalarını oluştur
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do      #dizine gir
    name = File.basename(dir)       #dizinin basename'ini al
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile     #presentation.cfg varsa onu yoksa default_conffile'ı confile'a ata
    config = File.open(conffile, "r") do |f|        #confile'ı aç 
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']     #config içerisinde key değeri landslide olanı al
    if ! landslide      #landslide yoksa 
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"       #hata ver çıktıyı ekrana bas       
      exit 1
    end

    if landslide['destination']     #lanslide var ve destination ayarı yapılmışsa
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"     #hata ver çıktıyı ekrana bas
      exit 1
    end

    if File.exists?('index.md')     #index.md dosyası var mı
      base = 'index'        #varsa dosya adını base'e ata
      ispublic = true       #genel sunum var
    elsif File.exists?('presentation.md')       #presentation.md var mı
      base = 'presentation'     #varsa dosya adını base'e ata
      ispublic = false      #genel sunum yok
    else        #diğer durumlarda
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"     #hata ver çıktıyı ekrana bas
      exit 1
    end

    basename = base + '.html'       #base'e atanan dosya adını html uzantılı yap
    thumbnail = File.to_herepath(base + '.png')     #resmin yolunu thumbnail'e ata
    target = File.to_herepath(basename)     #basename'in yolunu target'a ata

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }       #deps içindeki path'leri al
    deps.delete(target)     #target'a atananı sil
    deps.delete(thumbnail)      #thumbnail'e atananı sil

    tags = []       #etiket dizini

   presentation[dir] = {        #presentation içindeki görev çiftleri
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v|     #presentation içinde dolaş
  v[:tags].each do |t|      
    tag[t] ||= []       #etiket boşsa
    tag[t] << k     #k'yı ata
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]     #Hash içerisine görev çiftlerini ata

presentation.each do |presentation, data|       #sunumda dolaş
  ns = namespace presentation do        #isim uzayı oluştur
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'       #data[:basename], presentation.html'e denk değilse
          mv 'presentation.html', data[:basename]       #presentation.html'i data[:basename]'e taşı
        end
      end
    end

    file data[:thumbnail] => data[:target] do
      next unless data[:public]     #data[:public] yoksa devam et
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +     #verilen adresteki resmi al
          "--out=#{data[:thumbnail]} " +        #hedef dosyaya at
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +     #min. genişlik=1024
          "--min-height=768 " +     #min. yükseklik=768
          "--delay=1000"        #sunumlar arası geçiş süresi=1000
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])       #optimize edilen dosyayı data(:thumbnail)'e kaydet
    end

    task :optim do      
      chdir presentation do     #presentation dizinine gir
        optim       #resimleri optimize et
      end
    end

    task :index => data[:thumbnail]     #index görevini çalıştır

    task :build => [:optim, data[:target], :index]      #build görevini çalıştır

    task :view do       #view görevini çalıştır
      if File.exists?(data[:target])        #data[:target] var mı
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"     #varsa data[:directory]'e ulaş
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"      #yoksa hata ver çıktıyı ekrana bas
      end
    end

    task :run => [:build, :view]        #run görevi için build ve view görevini çalıştır

    task :clean do      #clean görevini çalıştır
      rm_f data[:target]        #data[:target]'ı sil
      rm_f data[:thumbnail]     #data[thumbnail]'ı sil
    end

    task :default => :build     #default görevi için build'i çalıştır
  end

  ns.tasks.map(&:to_s).each do |t|      #
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do     #p isim uzayını oluştur
  tasktab.each do |name, info|      #görev çiftlerini göster
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do        #build görevini çalıştır
    index = YAML.load_file(INDEX_FILE) || {}        #INDEX_FILE varsa al yoksa sözlük al
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']        #indeks yoksa ve presentations,index['presentations']'a denk değilse
      index['presentations'] = presentations        #presentations'ı index['presentations']'a ata
      File.open(INDEX_FILE, 'w') do |f|     #INDEX_FILE'ı yazılabilir aç
        f.write(index.to_yaml)      #index.to_yaml'a çevir
        f.write("---\n")        #"---\n" yaz
      end
    end
  end

  desc "sunum menüsü"       #sunum menüsü oluştur
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu      #menu yerine m yazarakta kullanılabilir yap
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
