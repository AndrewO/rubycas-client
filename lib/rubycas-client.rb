begin
  require 'casclient'
rescue MissingSourceFile
  require 'lib/casclient'
end

# make sure we're running inside Merb
if defined?(Merb::Plugins)

  # Use this hash in your Merb init.rb after calling rubycas-client as a dependency.
  # :cas_base_url is required and should point to your CAS server
  #
  # Example:
  # Merb::Plugins.config[:"rubycas-client"] = {
  #   :cas_base_url  => "https://cas.example.foo/",
  #   :login_url     => "https://cas.example.foo/login",
  #   :logout_url    => "https://cas.example.foo/logout",
  #   :validate_url  => "https://cas.example.foo/proxyValidate",
  #   :session_username_key => :cas_user,
  #   :session_extra_attributes_key => :cas_extra_attributes
  #   :logger => cas_logger
  # }
  Merb::Plugins.config[:"rubycas-client"] = {}
  
  # No rake tasks to add.  Uncomment if we add any.
  # Merb::Plugins.add_rakefiles "rubycas-client/merbtasks"
  
  require File.dirname(__FILE__) / 'casclient/frameworks/merb/filter'
else
  # If somehow this has been required before the Rails plugin's init
  require 'init'
end
