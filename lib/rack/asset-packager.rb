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
        
        # remove from the split packages too
        20.times do |n|
          split_asset_file_name =  "#{asset_file_name.gsub(".#{extension}", "")}_#{n}.#{extension}"
          F.delete(split_asset_file_name) if F.exists?(split_asset_file_name)
        end
      end
    end
    
    def self.package
      basic_package
      split_package
    end
    
    def self.basic_package
      each_asset do |asset_file_name, assets, extension, asset_dir|
        # standard packaging
        files = prepare_files assets, extension, asset_dir
        contents = `cat #{files.join(" ")}`
        if Rails.env.production?
          contents = compress_css(contents) if extension == "css"
          contents = compress_js(contents) if extension == "js"
        end
        F.open(asset_file_name, 'wb') { |f| f.write(contents) }
      end
    end
    
    def self.split_package
      each_asset do |asset_file_name, assets, extension, asset_dir|
        if extension == "css" && assets.length > 10 # only run for css right now
          # standard packaging
          files = prepare_files assets, extension, asset_dir
          # ie packaging - split into separate files if css - to handle ie7s limitations on filesize per stylesheet
          number_of_splits = (files.length / 10) + 1
          number_of_splits.times do |n|
            first = 0 + (n * 10) # split every 10 up.
            last = 9  + (n * 10)
            contents = `cat #{files[first..last].join(" ")}`
            if Rails.env.production?
              contents = compress_css(contents) if extension == "css"
            end
            F.open("#{asset_file_name.gsub(".#{extension}", '')}_#{n}.#{extension}", 'wb') { |f| f.write(contents) }
          end
        end
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
        filename_without_extension  = F.join asset_dir, "#{key}"
        filename                    = filename_without_extension + "." + extension
        
        # matches exactly
        if filename == path
          assets = prepare_files(config[key], extension, asset_dir)
          
          return [200, {
            "Content-Type"   => extension == "js" ? "text/javascript" : "text/css"
          }, `cat #{assets.join(" ")}`]
          
        # matches by starts_with -  i.e. "/stylesheets/application_package_0".starts_with?('/stylesheets/application_package')
        elsif path.starts_with?(filename_without_extension) 
          assets = prepare_files(config[key], extension, asset_dir)
          
          multiplier = path.gsub("#{filename_without_extension}_", '').gsub(".#{extension}", '').to_i rescue 0
          first = 0 + (multiplier * 10) # split every 10 up.
          last = 9  + (multiplier * 10)
          
          files = assets[first..last].join(" ") rescue nil
          if files
            return [200, {
              "Content-Type"   => extension == "js" ? "text/javascript" : "text/css"
            }, `cat #{files}`]
          end
        end
      end
      return false
    end
    
    def self.asset_stylesheet_link(package, options={})
      output = []
      if options[:ie7] == true && config[:stylesheets][package].length > 10
        length = config[:stylesheets][package].length
        number_of_packages = (length / 10) + 1
        number_of_packages.times do |n|
          output << "<link rel='stylesheet' href='/stylesheets/#{package.to_s}_#{n}.css' media='all' />"
        end
      elsif Rails.env.production?
        output << "<link rel='stylesheet' href='/stylesheets/#{package.to_s}.css' media='all' />"
      else
        output << "<link rel='stylesheet' href='/stylesheets/#{package.to_s}.css' media='all' />"
        # config[:stylesheets][package].each do |sheet|
        #   output << "<link rel='stylesheet' href='/stylesheets/#{sheet.to_s}.css' media='all' />"
        # end
      end
      
      output.join("\n")
    end
    
    def self.asset_javascript_link(package, options={})
      if options[:break_out] == true
        config[:javascripts][package].each do |script|
          output << "<script src='/javascripts/#{script.to_s}.js' type='text/javascript'></script>"
        end
      else
        output << "<script src='/javascripts/#{package.to_s}.js' type='text/javascript'></script>"
      end
      
      output.join("\n")
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