#!/usr/bin/ruby

require 'net/http'
require 'uri'
require 'RMagick'
#include Magick

class Vector2

  attr_accessor :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def Vector2.fromGeoCoords(lat, lon)
    Vector2.new(lon, Math.atanh(Math.sin(lat/180*Math::PI))/Math::PI*180)
  end

  def toGeoCoords()
    yrad = @y / 180 * Math::PI
    latrad = Math.atan( Math.sinh(yrad) )
    Vector2.new( @x, (latrad / Math::PI * 180) )
  end

  def *(arg)
    if Vector2 == arg.class
      Vector2.new(@x * arg.x, @y * arg.y)
    else
      Vector2.new(@x * arg, @y * arg)
    end
  end
  
  def /(arg)
    Vector2.new(@x / arg, @y / arg)
  end
  
  def +(arg)
    Vector2.new(@x + arg.x, @y + arg.y)
  end
  
  def -(arg)
    Vector2.new(@x - arg.x, @y - arg.y)
  end
  
  def toGeoString()
    yrad = @y / 180 * Math::PI
    latrad = Math.atan( Math.sinh(yrad) )
    (latrad / Math::PI * 180).to_s + ',' + @x.to_s
  end

  def toSizeString()
    @x.to_s + 'x' + @y.to_s
  end
    
end

class GoogleMap

  MAX_IMAGE_WIDTH = 640
  MAX_IMAGE_HEIGHT = 640
#  MAX_IMAGE_WIDTH = 256
#  MAX_IMAGE_HEIGHT = 256
  MAX_IMAGE_SIZE = Vector2.new(MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT)

  Format_JPEG = 'jpeg'
  Format_JPEG_Baseline = 'jpeg-baseline'
  Format_PNG8 = 'png8'
  Format_PNG32 = 'png32'
  Format_GIF = 'gif'

  Type_Roadmap = 'roadmap' # roadmap (default) specifies a standard roadmap image, as is normally shown on the Google Maps website. If no maptype value is specified, the Static Maps API serves roadmap tiles by default.
  Type_Mobile = 'mobile' # mobile specifies a mobile roadmap map image, which contains larger features and text fonts to enable easier visual display at the high resolutions and small screen sizes of mobile devices.
  Type_Satellite = 'satellite' # satellite specifies a satellite image.
  Type_Terrain = 'terrain' # terrain specifies a physical relief map image, showing terrain and vegetation.
  Type_Hybrid = 'hybrid' # hybrid specifies a hybrid of the satellite and roadmap image, showing a transparent layer of major streets and place names on the satellite image.
  Type_MapMaker_Roadmap = 'mapmaker-roadmap' # mapmaker-roadmap specifies a roadmap using tiles from Google Map Maker.
  Type_MapMaker_Hybrid = 'mapmaker-hybrid' # mapmaker-hybrid 

  attr_accessor :geoCenter, :geoSpan, :imageSize, :apiKey, :zoom, :imageFormat, :type
  attr_accessor :language, :sensor
  
  def initialize()
    @geoCenter = Vector2.new(0,0)
    @apiKey = ''
    @geoSpan = nil
    @imageSize = nil
    @imageFormat = Format_JPEG_Baseline
    @zoom = nil
    @type = Type_Roadmap
    @language = 'ru'
    @sensor = nil
  end

  def imageFormats
    return constants.find_all { |c| 0 == c.index('Format_') }
  end

  def types
    return constants.find_all { |c| 0 == c.index('Type_') }
  end

  def getUrl()
    url = 'http://maps.google.com/staticmap'
    url += '?center=' + geoCenter.toGeoString
    url += '&key=' + apiKey.to_s
    url += '&format=' + imageFormat.to_s
    url += '&maptype=' + type.to_s
    url += '&hl=' + language.to_s
    url += '&span=' + geoSpan.toGeoString if(geoSpan != nil)
    url += '&zoom=' + zoom.to_s if(zoom != nil)
    url += '&size=' + imageSize.toSizeString if(imageSize != nil)
    url += '&sensor=' + (sensor ? 'true' : 'false') if(sensor != nil)
    url
  end

  def download(path)
    url = URI.parse(getUrl)
    puts 'host: ' + url.host
    puts 'path: ' + url.path
    h = Net::HTTP.start(url.host, url.port) do |http|
      resp, data = http.get(url.path + '?' + url.query)
      File.open(path, 'wb') do |file|
        file.write(data)
      end
    end
  end

  
end

# -90..+90   (latitude, y)
# -180..+180 (longtitude, x)
# nfragments = 4^zoom
# fragment   = 256x256 px

#
# 1. get rect geo coords and zoom
# 2. zoom => pixel size in geo coords
# 3. => size of rect in pixels
# 4. split rect into 640x640 tiles
# 5. download tiles
# 6. compose single image:
#    http://www.imagemagick.org/RMagick/doc/image1.html#composite
# 7. calculate image geo coords
# 8. make map file
# 

def getPixelSize(zoom)
  fragsize = 2**zoom * 256
  Vector2.new(360.0 / fragsize, 360.0 / fragsize)
end

c = Vector2.fromGeoCoords(55.928817,37.758293)
z = 12
isize = Vector2.new(1000, 1000)
# c = Vector2.fromGeoCoords(0.0, 0.0)
# z = 1
# isize = Vector2.new(512, 512)

gm = GoogleMap.new
#gm.type = GoogleMap::Type_Satellite
gm.zoom = z
gm.imageSize = GoogleMap::MAX_IMAGE_SIZE

pixel_size = getPixelSize(z);

puts pixel_size.toGeoString

num_sect = Vector2.new(isize.x / GoogleMap::MAX_IMAGE_WIDTH,
                       isize.y / GoogleMap::MAX_IMAGE_HEIGHT)
last_sect_size = Vector2.new(isize.x % GoogleMap::MAX_IMAGE_WIDTH,
                             isize.y % GoogleMap::MAX_IMAGE_HEIGHT)
sect_geo_size = GoogleMap::MAX_IMAGE_SIZE * pixel_size
last_sect_geo_size = last_sect_size * pixel_size

img = Magick::Image.new(isize.x, isize.y);

img_nw_coord = Vector2.new(c.x - ((isize.x / 2.0) * pixel_size.x),
                           c.y + ((isize.y / 2.0) * pixel_size.y))
img_se_coord = Vector2.new(c.x + ((isize.x / 2.0) * pixel_size.x),
                           c.y - ((isize.y / 2.0) * pixel_size.y))

gm.geoCenter.y = img_nw_coord.y #+ isize.y * pixel_size.y
y = 0
while y < isize.y
  gm.imageSize.y = [GoogleMap::MAX_IMAGE_HEIGHT,
                            isize.y - y].min
  
  gm.geoCenter.y -= (gm.imageSize.y / 2.0) * pixel_size.y
  
  gm.geoCenter.x = img_nw_coord.x
  x = 0
  
  while x < isize.x
    gm.imageSize.x = [GoogleMap::MAX_IMAGE_WIDTH,
                              isize.x - x].min

    gm.geoCenter.x += (gm.imageSize.x / 2.0) * pixel_size.x

    fname = x.to_s + 'x' + y.to_s + '.jpg'
    print '(',x,',',y,') ',gm.getUrl,"\n"
#    gm.download(fname)
    tile = Magick::Image.read(fname)[0]
    p tile
    img.composite!(tile, x, y, Magick::CopyCompositeOp)

    gm.geoCenter.x += (gm.imageSize.x / 2.0) * pixel_size.x
    x += gm.imageSize.x
  end
  
  gm.geoCenter.y -= (gm.imageSize.y / 2.0) * pixel_size.y
  y += gm.imageSize.y
end

imgpath = '1.jpg'
mappath = '1.map'
img.write(imgpath)

vars = {}
vars['COPYRIGHT'] = 'test map'
vars['IMAGE_PATH'] = imgpath
vars['IMAGE_WIDTH'] = isize.x
vars['IMAGE_HEIGHT'] = isize.y
vars['INIT_X'] = 0
vars['INIT_Y'] = 0
vars['SCALE'] = 1.0 # ???

geo_nw = img_nw_coord.toGeoCoords
geo_se = img_se_coord.toGeoCoords
vars['NW_LAT'] = geo_nw.y
vars['NW_LAT_DEG'] = geo_nw.y.truncate
vars['NW_LAT_MIN'] = (geo_nw.y - geo_nw.y.truncate).abs * 60.0
vars['NW_LAT_HEMI'] = geo_nw.y > 0 ? 'N' : 'S'

vars['NW_LON'] = geo_nw.x
vars['NW_LON_DEG'] = geo_nw.x.truncate
vars['NW_LON_MIN'] = (geo_nw.x - geo_nw.x.truncate).abs * 60.0
vars['NW_LON_HEMI'] = geo_nw.x > 0 ? 'E' : 'W'

vars['SE_LAT'] = geo_se.y
vars['SE_LAT_DEG'] = geo_se.y.truncate
vars['SE_LAT_MIN'] = (geo_se.y - geo_se.y.truncate).abs * 60.0
vars['SE_LAT_HEMI'] = geo_se.y > 0 ? 'N' : 'S'

vars['SE_LON'] = geo_se.x
vars['SE_LON_DEG'] = geo_se.x.truncate
vars['SE_LON_MIN'] = (geo_se.x - geo_se.x.truncate).abs * 60.0
vars['SE_LON_HEMI'] = geo_se.x > 0 ? 'E' : 'W'

File.open(mappath, 'w') do |file|
  File.foreach('template.map') do |line|
    vars.each do |name, value|
      line.gsub!('%' + name + '%', value.to_s)
    end
    file.puts line
  end
end

exit

gm = GoogleMap.new
gm.geoCenter = Vector2.new(55.928817,37.758293)
gm.zoom = 12
#gm.geoSpan = Vector2.new(180, 360)
gm.imageSize = Vector2.new(256, 256)
#http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=%D0%BC%D0%BE%D1%81%D0%BA%D0%B2%D0%B0+%D0%BC%D1%8B%D1%82%D0%B8%D1%89%D0%B8&sll=37.0625,-95.677068&sspn=30.130288,56.337891&ie=UTF8&ll=55.928817,37.758293&spn=0.08309,0.22007&t=h&z=12
#http://maps.google.com/?ie=UTF8&ll=37.0625,-95.677068&spn=30.130288,56.337891&z=4
#http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=%D0%BC%D1%8B%D1%82%D0%B8%D1%89%D0%B8+%D1%81%D0%B8%D0%BB%D0%B8%D0%BA%D0%B0%D1%82%D0%BD%D0%B0%D1%8F&sll=37.0625,-95.677068&sspn=30.130288,56.337891&ie=UTF8&ll=55.940068,37.779236&spn=0.041533,0.110035&z=13
#http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=%D0%BC%D1%8B%D1%82%D0%B8%D1%89%D0%B8+%D1%81%D0%B8%D0%BB%D0%B8%D0%BA%D0%B0%D1%82%D0%BD%D0%B0%D1%8F&sll=37.0625,-95.677068&sspn=30.130288,56.337891&ie=UTF8&ll=55.935116,37.780867&spn=0.020769,0.055017&z=14
puts gm.getUrl
gm.download('2.jpg')

