require 'time'
require 'rack/file'
require 'rack/utils'

module Rack
  class AssetPackager
    F = ::File
    
    attr_accessor :urls, :root
    DEFAULTS = {:static => true}
    
    def initialize(app, opts={})
      opts = DEFAULTS.merge(opts)
      @app = app
      
      @urls = *opts[:urls] || '/javascripts'
      @root = opts[:root] || Dir.pwd
      @command = 'coffee -p'
      
      @javascript_dir = F.join "/", "javascripts"
      @stylesheet_dir = F.join "/", "stylesheets"

      @config = YAML.load_file 'config/assets.yml'
    end
    
    def brew(coffee)
      javascript = coffee.sub('.coffee', '.js')
      if F.exists?(coffee) && (!F.exists?(javascript) || F.mtime(javascript) < F.mtime(coffee))
        contents = `#{@command} #{coffee}`
        F.delete(javascript) if F.exists?(javascript)
        F.open(javascript, 'wb') { |f| f.write( contents ) }
      end
    end
    
    def concat(path, config, asset_dir, extension)
      for key in config.keys
        filename = F.join asset_dir, "#{key}." + extension
        if filename == path
          config = config[key]
          assets = config.map do |c| 
            base = F.join @root, asset_dir, c
            brew(base + '.coffee') if extension == "js"
            "#{base}.#{extension}"
          end
          F.open(F.join(@root, filename), 'wb') { |f| f.write( `cat #{assets.join(" ")}` ) } 
        end
      end
    end
    
    def call(env)
      path = Utils.unescape(env["PATH_INFO"])
      return [403, {"Content-Type" => "text/plain"}, ["Forbidden\n"]] if path.include?('..')
      
      concat(path, @config["javascripts"], @javascript_dir, "js") if path =~ /^#{@javascript_dir}/
      concat(path, @config["stylesheets"], @stylesheet_dir, "css") if path =~ /^#{@stylesheet_dir}/
      
      return @app.call(env)
    end
  end
end