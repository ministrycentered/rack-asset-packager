require 'time'
require 'rack/file'
require 'rack/utils'
require "yui/compressor"
require 'closure-compiler'

module Rack
  class AssetPackager
    F = ::File
    
    def config
      Rack::AssetPackager.config
    end

    def self.config
      config = YAML.load_file('config/assets.yml').with_indifferent_access
      config
    end
    
    def settings
      Rack::AssetPackager.settings
    end
    
    def self.settings
      settings = {}
      settings[:root] ||= "#{RAILS_ROOT}/public" #Dir.pwd
      settings[:coffee] ||= 'coffee -p'
      settings[:server] = Rack::File.new(settings[:root])
      settings[:javascript_dir] = F.join "/", "javascripts"
      settings[:stylesheet_dir] = F.join "/", "stylesheets"
      settings
    end
    
    def self.each_asset(&block)
      for key in config.keys
        next if key.to_sym == :settings
        puts "#{key.upcase}"
        extension = key == "javascripts" ? "js" : "css"
        asset_dir = key == "javascripts" ? settings[:javascript_dir] : settings[:stylesheet_dir]
        for asset in config[key].keys
          puts " - #{asset}.#{extension}"
          asset_file_name = F.join settings[:root], asset_dir, "#{asset}.#{extension}"
          yield asset_file_name, config[key][asset], extension, asset_dir
        end
      end
    end

    def self.remove_packages
      each_asset do |asset_file_name, assets, extension, asset_dir|
        F.delete(asset_file_name) if F.exists?(asset_file_name)
      end
    end
    
    def self.package
      each_asset do |asset_file_name, assets, extension, asset_dir|
        files = prepare_files assets, extension, asset_dir
        contents = `cat #{files.join(" ")}`
        contents = compress_css(contents) if extension == "css"
        contents = compress_js(contents) if extension == "js"
        F.open(asset_file_name, 'wb') { |f| f.write(contents) }
      end
    end
    
    def self.compress_css(css)
      YUI::CssCompressor.new.compress(css)
    end
    
    def self.compress_js(js)
      # YUI::JavaScriptCompressor.new.compress(js)
      Closure::Compiler.new.compile(js)
    end
    
    def prepare_files(files, extension, asset_dir)
      Rack::AssetPackager.prepare_files(files, extension, asset_dir)
    end

    def self.prepare_files(files, extension, asset_dir)
      assets = files.map do |c| 
        base = F.join settings[:root], asset_dir, c
        brew(base + '.coffee') if extension == "js"
        "#{base}.#{extension}"
      end
      assets
    end
    
    def initialize(app)
      @app = app
    end
    
    def self.brew(coffee)
      javascript = coffee.sub('.coffee', '.js')
      if F.exists?(coffee) && (!F.exists?(javascript) || F.mtime(javascript) < F.mtime(coffee))
        contents = `#{settings[:coffee]} #{coffee}`
        F.delete(javascript) if F.exists?(javascript)
        F.open(javascript, 'wb') { |f| f.write( contents ) }
      end
    end
    
    def concat(path, config, asset_dir, extension)
      for key in config.keys
        filename = F.join asset_dir, "#{key}." + extension
        if filename == path
          assets = prepare_files(config[key], extension, asset_dir)
          return [200, {
            "Content-Type"   => extension == "js" ? "text/javascript" : "text/css"
          }, `cat #{assets.join(" ")}`]
        end
      end
      return false
    end
    
    def call(env)
      path = Utils.unescape(env["PATH_INFO"])
      return [403, {"Content-Type" => "text/plain"}, ["Forbidden\n"]] if path.include?('..')
      
      if path =~ /^#{settings[:javascript_dir]}/
        server_call = concat(path, config[:javascripts], settings[:javascript_dir], "js") 
        return server_call if server_call 
      end
      if path =~ /^#{settings[:stylesheet_dir]}/
        server_call = concat(path, config[:stylesheets], settings[:stylesheet_dir], "css") 
        return server_call if server_call 
      end
      
      return @app.call(env)
    end
  end
end