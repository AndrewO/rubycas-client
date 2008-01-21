module CASClient
  # The client brokers all HTTP transactions with the CAS server.
  class Client
    attr_reader :cas_base_url 
    attr_reader :log, :username_session_key, :extra_attributes_session_key
    attr_writer :login_url, :validate_url, :proxy_url, :logout_url, :service_url
    attr_accessor :proxy_callback_url, :proxy_retrieval_url
    
    def initialize(conf = nil)
      configure(conf) if conf
    end
    
    def configure(conf)
      raise ArgumentError, "Missing :cas_base_url parameter!" unless conf[:cas_base_url]
      
      @cas_base_url      = conf[:cas_base_url].gsub(/\/$/, '')       
      
      @login_url    = conf[:login_url]
      @logout_url   = conf[:logout_url]
      @validate_url = conf[:validate_url]
      @proxy_url    = conf[:proxy_url]
      @service_url  = conf[:service_url]
      @proxy_callback_url  = conf[:proxy_callback_url]
      @proxy_retrieval_url = conf[:proxy_retrieval_url]
      
      @username_session_key         = conf[:username_session_key] || :cas_user
      @extra_attributes_session_key = conf[:extra_attributes_session_key] || :cas_extra_attributes
      
      @log = CASClient::LoggerWrapper.new
      @log.set_real_logger(conf[:logger]) if conf[:logger]
    end
    
    def login_url
      @login_url || (cas_base_url + "/login")
    end
    
    def validate_url
      @validate_url || (cas_base_url + "/proxyValidate")
    end
    
    # Returns the CAS server's logout url.
    #
    # If a logout_url has not been explicitly configured,
    # the default is cas_base_url + "/logout".
    #
    # service_url:: Set this if you want the user to be
    #               able to immediately log back in. Generally
    #               you'll want to use something like <tt>request.referer</tt>.
    #               Note that this only works with RubyCAS-Server.
    # back_url:: This satisfies section 2.3.1 of the CAS protocol spec.
    #            See http://www.ja-sig.org/products/cas/overview/protocol
    def logout_url(service_url = nil, back_url = nil)
      url = @logout_url || (cas_base_url + "/logout")
      
      if service_url || back_url
        uri = URI.parse(url)
        h = uri.query ? query_to_hash(uri.query) : {}
        h['service'] = service_url if service_url
        h['url'] = back_url if back_url
        uri.query = hash_to_query(h)
        uri.to_s
      else
        url
      end
    end
    
    def proxy_url
      @proxy_url || (cas_base_url + "/proxy")
    end
    
    def validate_service_ticket(st)
      uri = URI.parse(validate_url)
      h = uri.query ? query_to_hash(uri.query) : {}
      h['service'] = st.service
      h['ticket'] = st.ticket
      h['renew'] = 1 if st.renew
      h['pgtUrl'] = proxy_callback_url if proxy_callback_url
      uri.query = hash_to_query(h)
      
      st.response = request_cas_response(uri, ValidationResponse)
      
      return st
    end
    alias validate_proxy_ticket validate_service_ticket
    
    # Requests a login using the given credentials for the given service; 
    # returns a LoginResponse object.
    def login_to_service(credentials, service)
      lt = request_login_ticket
      
      data = credentials.merge(
        :lt => lt,
        :service => service 
      )
      
      res = submit_data_to_cas(login_url, data)
      CASClient::LoginResponse.new(res)
    end
  
    # Requests a login ticket from the CAS server for use in a login request;
    # returns a LoginTicket object.
    #
    # This only works with RubyCAS-Server, since obtaining login
    # tickets in this manner is not part of the official CAS spec.
    def request_login_ticket
      uri = URI.parse(login_url+'Ticket')
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = (uri.scheme == 'https')
      res = https.post(uri.path, ';')
      
      raise CASException, res.body unless res.kind_of? Net::HTTPSuccess
      
      res.body.strip
    end
    
    # Requests a proxy ticket from the CAS server for the given service
    # using the given pgt (proxy granting ticket); returns a ProxyTicket 
    # object.
    #
    # The pgt required to request a proxy ticket is obtained as part of
    # a ValidationResponse.
    def request_proxy_ticket(pgt, target_service)
      uri = URI.parse(proxy_url)
      h = uri.query ? query_to_hash(uri.query) : {}
      h['pgt'] = pgt.ticket
      h['targetService'] = target_service
      uri.query = hash_to_query(h)
      
      pr = request_cas_response(uri, ProxyResponse)
      
      pt = ProxyTicket.new(pr.proxy_ticket, target_service)
      pt.response = pr
      
      return pt
    end
    
    def retrieve_proxy_granting_ticket(pgt_iou)
      uri = URI.parse(proxy_retrieval_url)
      uri.query = (uri.query ? uri.query + "&" : "") + "pgtIou=#{CGI.escape(pgt_iou)}"
      retrieve_url = uri.to_s
      
      log.debug "Retrieving PGT for PGT IOU #{pgt_iou.inspect} from #{retrieve_url.inspect}"
      
#      https = Net::HTTP.new(uri.host, uri.port)
#      https.use_ssl = (uri.scheme == 'https')
#      res = https.post(uri.path, ';')
      uri = URI.parse(uri) unless uri.kind_of? URI
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = (uri.scheme == 'https')
      res = https.start do |conn|
        conn.get("#{uri.path}?#{uri.query}")
      end
      
      
      raise CASException, res.body unless res.kind_of? Net::HTTPSuccess
      
      ProxyGrantingTicket.new(res.body.strip, pgt_iou)
    end
    
    def add_service_to_login_url(service_url)
      uri = URI.parse(login_url)
      uri.query = (uri.query ? uri.query + "&" : "") + "service=#{CGI.escape(service_url)}"
      uri.to_s
    end
    
    private
    # Fetches a CAS response of the given type from the given URI.
    # Type should be either ValidationResponse or ProxyResponse.
    def request_cas_response(uri, type)
      log.debug "Requesting CAS response form URI #{uri.inspect}"
      
      uri = URI.parse(uri) unless uri.kind_of? URI
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = (uri.scheme == 'https')
      raw_res = https.start do |conn|
        conn.get("#{uri.path}?#{uri.query}")
      end
      
      #TODO: check to make sure that response code is 200 and handle errors otherwise
      
      log.debug "CAS Responded with #{raw_res.inspect}:\n#{raw_res.body}"
      
      type.new(raw_res.body)
    end
    
    # Submits some data to the given URI and returns a Net::HTTPResponse.
    def submit_data_to_cas(uri, data)
      uri = URI.parse(uri) unless uri.kind_of? URI
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data(data, ';')
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = (uri.scheme == 'https')
      https.start {|conn| conn.request(req) }
    end
    
    def query_to_hash(query)
      CGI.parse(query)
    end
      
    def hash_to_query(hash)
      pairs = []
      hash.each do |k, vals|
        vals = [vals] unless vals.kind_of? Array
        vals.each {|v| pairs << "#{CGI.escape(k)}=#{CGI.escape(v)}"}
      end
      pairs.join("&")
    end
  end
end