
require 'net/http'
require 'uri'

# 2D vector
class Vector2

  attr_accessor :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def *(arg)
    if Vector2 == arg.class
      Vector2.new(@x * arg.x, @y * arg.y)
    else
      Vector2.new(@x * arg, @y * arg)
    end
  end
  
  def /(arg)
    if Vector2 == arg.class
      Vector2.new(@x / arg.x, @y / arg.y)
    else
      Vector2.new(@x / arg, @y / arg)
    end
  end
  
  def +(arg)
    Vector2.new(@x + arg.x, @y + arg.y)
  end
  
  def -(arg)
    Vector2.new(@x - arg.x, @y - arg.y)
  end

  def abs()
    Vector2.new(@x.abs, @y.abs)
  end

  def abs!()
    @x = @x.abs
    @y = @y.abs
    self
  end

  def to_s()
    @x.to_s + 'x' + @y.to_s
  end
  
end

def deg2rad(th)
  th / 180.0 * Math::PI
end

def rad2deg(th)
  th / Math::PI * 180.0
end

# geographical location
class GeoPoint
  
  attr_accessor :lat, :lon

  def initialize(lat, lon)
    @lat = lat
    @lon = lon
  end

  def toProjection()
    Vector2.new( @lon, Math.atanh( Math.sin(@lat) ) )
  end

  def GeoPoint.fromProjection(p)
    GeoPoint.new( Math.atan( Math.sinh(p.y) ), p.x)
  end

  def lat_deg
    rad2deg(@lat)
  end

  def lat_min
    deg = self.lat_deg
    (deg - deg.truncate).abs * 60.0
  end

  def lat_sec
    min = self.lat_min
    (min - min.truncate) * 60.0
  end

  def lon_deg
    rad2deg(@lon)
  end

  def lon_min
    deg = self.lon_deg
    (deg - deg.truncate).abs * 60.0
  end

  def lon_sec
    min = self.lon_min
    (min - min.truncate) * 60.0
  end

  def to_s()
    self.lat_deg.to_s + ',' + self.lon_deg.to_s
  end

  def GeoPoint.from_s(str)
    lat, lon = str.scan(/\d+\.\d+/)
    GeoPoint.new(deg2rad(lat.to_f), deg2rad(lon.to_f))
  end
  
end

class String
  def to_GeoPoint()
    GeoPoint.from_s(self)
  end
end

# google maps static api wrapper
class GoogleMap

  MAX_IMAGE_WIDTH = 640
  MAX_IMAGE_HEIGHT = 640
  MAX_IMAGE_SIZE = Vector2.new(MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT)

  MAX_ZOOM = 19

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
    @language = nil
    @sensor = nil
  end

  # image formats
  def imageFormats
    return constants.find_all { |c| 0 == c.index('Format_') }
  end

  # map types
  def types
    return constants.find_all { |c| 0 == c.index('Type_') }
  end

  # make map url from given parameters
  def getUrl()
    url = 'http://maps.google.com/staticmap'
    url += '?center=' + @geoCenter.to_s
    url += '&key=' + @apiKey.to_s
    url += '&format=' + @imageFormat.to_s
    url += '&maptype=' + @type.to_s
    url += '&hl=' + @language.to_s if @language != nil
    url += '&span=' + @geoSpan.to_s if @geoSpan != nil
    url += '&zoom=' + @zoom.to_s if @zoom != nil
    url += '&size=' + @imageSize.to_s if @imageSize != nil
    url += '&sensor=' + (@sensor ? 'true' : 'false') if @sensor != nil
    url
  end

  # fill some parameters from url
  def parseUrl(url)
    @zoom = $1.to_i if url =~ /[?&]zoom=([^&]*)/
    @geoCenter = $1.to_GeoPoint if url =~ /[?&]ll=([^&]*)/
    @geoSpan = $1.to_GeoPoint if url =~ /[?&]span=([^&]*)/
    @language = $1.to_s if url =~ /[?&]hl=([^&]*)/
    self
  end

  # download map into memory
  # returns image data
  def save2blob()
    url = URI.parse(getUrl)
    h = Net::HTTP.start(url.host, url.port) do |http|
      resp, data = http.get(url.path + '?' + url.query)
      return data
    end
  end

  # download map into file
  def save2file(path)
    File.write(path, save2blob())
  end

  # returns (Vector2) size of pixel in projection coordinates
  def GoogleMap.getPixelSize(zoom)
    fragsize = 2**zoom * 256
    Vector2.new(2.0 * Math::PI / fragsize, 2.0 * Math::PI / fragsize)
  end

  # returns (Vector2) size of pixel in projection coordinates
  def pixelSize()
    GoogleMap.getPixelSize(@zoom)
  end

  # create maps to fill region
  # nw:        north-west region projection coordinate
  # zoom:      map zoom
  # img_size:  full region image size
  # tile_size: tile size (south-east tiles will be smaller)
  # block:     callback(image_position, google_map)
  def GoogleMap.makeTiles(nw, zoom, img_size, tile_size)

    pix_size = GoogleMap.getPixelSize(zoom)
    
    geo_pos = Vector2.new(0, nw.y)
    img_pos = Vector2.new(0, 0)
    while img_pos.y < img_size.y
      # height is either tile height or all space left
      img_h = [tile_size.y, img_size.y - img_pos.y].min
      
      geo_pos.y -= (img_h / 2.0) * pix_size.y
      
      geo_pos.x = nw.x
      img_pos.x = 0
      
      while img_pos.x < img_size.x
        img_w = [tile_size.x, img_size.x - img_pos.x].min

        geo_pos.x += (img_w / 2.0) * pix_size.x

        map = GoogleMap.new
        map.geoCenter = GeoPoint.fromProjection(geo_pos)
        map.zoom = zoom
        map.imageSize = Vector2.new(img_w, img_h)

        yield img_pos, map

        geo_pos.x += (img_w / 2.0) * pix_size.x
        img_pos.x += img_w
      end
      
      geo_pos.y -= (img_h / 2.0) * pix_size.y
      img_pos.y += img_h
    end
  end

end

