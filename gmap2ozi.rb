#!/usr/bin/ruby

# == Synopsis
#
# Program for creating Ozi Explorer maps from google static maps
#
# == Usage
#
# gmap2ozi [OPTIONS] map_file [image_file]
#
# -?, --help:
#    show help
#
# -l, --language:
#    set 2-letter language code
#
# map_file:
#    generated map file name
#
# image_file:
#    map's image file name
#
# IMAGE PARAMETERS:
#  The following parameters define map image.
#
# -w, --image-width WIDTH:
#    set image width
#
# -h, --image-height HEIGHT:
#    set image height
#
# -z, --image-zoom ZOOM:
#    set image size to cover region with given zoom value
#
# -t, --image-type TYPE:
#    set image type (default: jpeg)
#    TYPE must be one of jpeg, jpeg-baseline, png8, png32, gif
#
# --no-download:
#    don't download anything - create blank image
#
# REGION PARAMETERS:
#  The following parameters define geographical region to render.
# 
# -c, --region-center LAT,LON:
#    set region center
#
# -n, --region-ne LAT,LON:
#    set region north-east corner
#
# -s, --region-sw LAT,LON:
#    set region south-west corner
#
# -p, --region-size LAT,LON:
#    set region size
#
# -x, --region-pixel-size ZOOM,WIDTH,HEIGHT:
#    set region size in pixels for given zoom value
#
# -u, --region-from-url WIDTH,HEIGHT,URL:
#    set region parameters from google maps url
#    this option works like combination of -c and -x options
#

require 'getoptlong'
require 'rdoc/usage'
require 'RMagick'
require 'google_map'

# read agruments
opts = GetoptLong.new(
                      [ '--help', '-?', GetoptLong::NO_ARGUMENT ],
                      [ '--language', '-l', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--no-download', '', GetoptLong::NO_ARGUMENT ],
                      [ '--image-width', '-w', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--image-height', '-h', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--image-zoom', '-z', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--image-type', '-t', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-center', '-c', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-ne', '-n', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-sw', '-s', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-size', '-p', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-pixel-size', '-x', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--region-from-url', '-u', GetoptLong::REQUIRED_ARGUMENT ]
                      )

# default option values
image_width = nil
image_height = nil
image_zoom = nil
image_type = 'jpeg'
region_center = nil
region_ne = nil
region_sw = nil
region_size = nil
lang = nil
no_donwload = false

opts.each do |opt, arg|
  case opt
  when '--help'
    RDoc::usage
    exit 0
  when '--no-download'
    no_download = true
  when '--language'
    lang = arg
  when '--image-width'
    image_width = arg.to_i
  when '--image-height'
    image_height = arg.to_i
  when '--image-zoom'
    image_zoom = arg.to_i
  when '--image-type'
    image_type = arg
  when '--region-center'
    region_center = GeoPoint.from_s(arg).toProjection
  when '--region-ne'
    region_ne = GeoPoint.from_s(arg).toProjection
  when '--region-sw'
    region_sw = GeoPoint.from_s(arg).toProjection
  when '--region-size'
    region_size = GeoPoint.from_s(arg).toProjection
  when '--region-pixel-size'
    zoom, w, h = arg.scan(/\d+/)
    pix_size = GoogleMap.getPixelSize(zoom.to_i)
    region_size = Vector2.new(w.to_i * pix_size.x, h.to_i * pix_size.y)
  when '--region-from-url'
    w, h, url = arg.split(/,/)
    GoogleMap m = GoogleMap.new.parseUrl(url)
    pix_size = m.pixelSize
    region_size = Vector2.new(w.to_i * pix_size.x, h.to_i * pix_size.y)
  end
end

abort 'Missing map file name' if ARGV.length < 1

map_path = File.expand_path(ARGV.shift)

if ARGV.length > 0
  img_path = File.expand_path(ARGV.shift)
else
  img_path = map_path[0..-File.extname(map_path).length] +
    case image_type
    when 'jpeg' then 'jpg'
    when 'jpeg-baseline' then 'jpg'
    when 'png8' then 'png'
    when 'png32' then 'png32'
    when 'gif' then 'gif'
    else image_type
    end
end

# 1. calc region size
# 2. if image_zoom == nil, find best image_zoom for given image size
# 3. calc image size
# 4. calc region center
# 5. calc region nw point

if nil == region_size
  if nil != region_ne && nil != region_sw
    region_size = (region_ne - region_sw).abs
  elsif nil != region_center && nil != region_ne
    region_size = (region_ne - region_center).abs * 2
  elsif nil != region_center && nil != region_sw
    region_size = (region_sw - region_center).abs * 2
  elsif nil != image_width && nil != image_height && nil != image_zoom
    pix_size = GoogleMap.getPixelSize(image_zoom)
    region_size = Vector2.new(image_width * pix_size.x, image_height * pix_size.y)
  else
    abort 'Not enough parameters to calculate region size'
  end
end

if nil == image_zoom
  if nil == image_width || nil == image_height
    abort 'Not enough parameters to calculate image size'
  end

  # calc pixel size
  ps_x = region_size.x / width
  ps_y = region_size.y / height
  # get the smallest one (for max zoom)
  ps = ps_x < ps_y ? ps_x : ps_y
  # calc zoom
  zoom = log( 2.0 * Math.PI / ( ps * 256 ) ) / Math.log(2)
  zoom = zoom.ceil
  zoom = GoogleMap::MAX_ZOOM if zoom > GoogleMap::MAX_ZOOM

end

image_size = region_size / GoogleMap.getPixelSize(image_zoom)
image_size = Vector2.new(image_size.x.round, image_size.y.round)

if nil == region_center
  if nil != region_ne && nil != region_sw
    region_center = (region_ne + region_sw) / 2
  elsif nil != region_ne
    region_center = region_ne - region_size / 2
  elsif nil != region_sw
    region_center = region_sw + region_size / 2
  else
    abort 'Not enough parameters to calculate region center'
  end
end

region_nw = Vector2.new(region_center.x - region_size.x / 2,
                        region_center.y + region_size.y / 2) 
region_se = Vector2.new(region_center.x + region_size.x / 2,
                        region_center.y - region_size.y / 2) 

#raise "TEST!!!"
# -c 55.928817,37.758293 -z 12 -w 1000 -h 1000 -l ru -t jpeg 1.map
# c = GeoPoint.new(deg2rad(55.928817), deg2rad(37.758293)).toProjection()
# z = 12
# isize = Vector2.new(1000, 1000)

# img_path = '1.jpg'
# map_path = img_path + '.map'

# c = Vector2.fromGeoCoords(0.0, 0.0)
# z = 1
# isize = Vector2.new(512, 512)

# gm = GoogleMap.new
# #gm.type = GoogleMap::Type_Satellite
# gm.zoom = z
# gm.imageSize = GoogleMap::MAX_IMAGE_SIZE

# pixel_size = gm.pixelSize;

# puts pixel_size.to_s

# num_sect = Vector2.new(isize.x / GoogleMap::MAX_IMAGE_WIDTH,
#                        isize.y / GoogleMap::MAX_IMAGE_HEIGHT)
# last_sect_size = Vector2.new(isize.x % GoogleMap::MAX_IMAGE_WIDTH,
#                              isize.y % GoogleMap::MAX_IMAGE_HEIGHT)
# sect_geo_size = GoogleMap::MAX_IMAGE_SIZE * pixel_size
# last_sect_geo_size = last_sect_size * pixel_size

img = Magick::Image.new(image_size.x, image_size.y);

# proj rect, zoom, tile size, 
# img_nw_coord = Vector2.new(c.x - ((isize.x / 2.0) * pixel_size.x),
#                            c.y + ((isize.y / 2.0) * pixel_size.y))
# img_se_coord = Vector2.new(c.x + ((isize.x / 2.0) * pixel_size.x),
#                            c.y - ((isize.y / 2.0) * pixel_size.y))

GoogleMap.makeTiles(region_nw, image_zoom,
                    image_size, GoogleMap::MAX_IMAGE_SIZE) do |pos, map|
  map.language = lang
  map.imageFormat = image_type
  print '(',pos.x,',',pos.y,') ',map.getUrl,"\n"
  #  p map
  if !no_download
    blob = map.save2blob
    #  fname = pos.x.to_s + 'x' + pos.y.to_s + '.jpg'
    #  blob = File.read(fname)
    tile = Magick::Image.from_blob(blob)[0]
    p tile
    img.composite!(tile, pos.x, pos.y, Magick::CopyCompositeOp)
  end
end

img.write(img_path)

vars = {}
vars['COPYRIGHT'] = 'test map'
vars['IMAGE_PATH'] = File.dirname(img_path) == File.dirname(map_path) ? File.basename(img_path) : img_path
vars['IMAGE_WIDTH'] = image_size.x
vars['IMAGE_HEIGHT'] = image_size.y
vars['INIT_X'] = 0
vars['INIT_Y'] = 0
vars['SCALE'] = 1.0 # ???

geo_nw = GeoPoint.fromProjection(region_nw)
geo_se = GeoPoint.fromProjection(region_se)
vars['NW_LAT'] = geo_nw.lat_deg
vars['NW_LAT_DEG'] = geo_nw.lat_deg.abs.truncate
vars['NW_LAT_MIN'] = geo_nw.lat_min
vars['NW_LAT_HEMI'] = geo_nw.lat > 0 ? 'N' : 'S'

vars['NW_LON'] = geo_nw.lon_deg
vars['NW_LON_DEG'] = geo_nw.lon_deg.abs.truncate
vars['NW_LON_MIN'] = geo_nw.lon_min
vars['NW_LON_HEMI'] = geo_nw.lon > 0 ? 'E' : 'W'

vars['SE_LAT'] = geo_se.lat_deg
vars['SE_LAT_DEG'] = geo_se.lat_deg.abs.truncate
vars['SE_LAT_MIN'] = geo_se.lat_min
vars['SE_LAT_HEMI'] = geo_se.lat > 0 ? 'N' : 'S'

vars['SE_LON'] = geo_se.lon_deg
vars['SE_LON_DEG'] = geo_se.lon_deg.abs.truncate
vars['SE_LON_MIN'] = geo_se.lon_min
vars['SE_LON_HEMI'] = geo_se.lon > 0 ? 'E' : 'W'

print 'Writing map to ', map_path, "\n"
File.open(map_path, 'w') do |file|
  File.foreach('template.map') do |line|
    vars.each do |name, value|
      line.gsub!('%' + name + '%', value.to_s)
    end
    file.puts line
  end
end

puts 'Done.'


