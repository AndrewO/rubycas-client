# Run from this directory with merb -I sample_merb_app.rb

require 'ruby-debug'

$:.unshift(File.dirname(__FILE__) / ".." / ".." / "lib")
require "rubycas-client"

Merb::Router.prepare do |r|
  r.match('/').to(:controller => 'sample_merb_app', :action =>'index')
  r.default_routes
end

class SampleMerbApp < Merb::Controller
  include CASClient::Frameworks::Merb::Filter
  before :cas_filter
  
  def index
    "hi, #{session[:cas_user]}"
  end
end

Merb::Config.use { |c|
  c[:environment]         = 'development',
  c[:framework]           = {},
  c[:log]                 = File.dirname(__FILE__)
  c[:log_level]           = 'debug',
  c[:use_mutex]           = false,
  c[:session_store]       = 'cookie',
  c[:session_secret_key]  = '9f30c015f2132d217bfb81e31668a74fadbdf672',
  c[:exception_details]   = true,
  c[:reload_classes]      = true,
  c[:reload_time]         = 0.5
}

Merb::Plugins.config[:"rubycas-client"] = {
  :cas_base_url => "http://localhost:443"
}
