#
# RackService
#
# A Rack application and API parent class to make a Ruby object into a web service API.
#

require 'logger'
require 'rack'

module RackService
  class API
    HTTP_METHODS = [:GET, :POST, :PUT, :DELETE]
    def api_methods
      self.class.api_instance_methods
    end
    HTTP_METHODS.each{|hm| define_method("#{hm.downcase}_methods"){ api_methods.select{|m,h|h==hm}.map{|m,_|m} }}
    class << self
      def api_instance_methods
        @api_instance_methods ||= {}
      end
      def api(http_method, *instance_methods)
        public *instance_methods
        if instance_methods.empty?
          @api_next = http_method
        else
          instance_methods.each{|m| api_instance_methods[m] = http_method}
        end
      end
      HTTP_METHODS.each{|hm| define_method(hm.downcase){|*methods| api(hm, *methods) }}
      def method_added(m)
        api(@api_next || HTTP_METHODS.first, m) if public_instance_methods(false).include? m
      end
    end
  end
  class Request < Rack::Request
    attr_reader :cmd, :args, :named_args
    def initialize(env)
      super env
      _, @cmd, *@args = path_info.split('/').map {|e| Rack::Utils::unescape e}
      @cmd = cmd.to_sym rescue nil
      ignore_params = env['HTTP_X_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []
      @named_args = Hash[params.reject{|k,v| ignore_params.include? k}.map{|k,v| [k.to_sym,v]}]
    end
  end
  class App
    HTTP_OK = 200
    HTTP_BAD_REQUEST = 400
    HTTP_NOT_FOUND = 404
    HTTP_METHOD_NOT_ALLOWED = 405
    def initialize(api, *api_args, log:Logger.new(STDERR), **api_named_args)
      @log = log
      @log.formatter = lambda{|_,time,_,msg| req = Thread.current[:req]
        "#{time.strftime '%FT%T%z'} #{req.ip} #{[req.referer, req.user_agent].map{|s|(s||'-').inspect}.join(' ')} #{req.cmd} #{msg}\n"
      }
      @api = api.new(*api_args, log: log, **api_named_args)
      @version = %x{cd #{File.dirname(caller_locations(1,1)[0].path)}; git describe --match 'v*'}.chomp
    end
    def helptext(req)
      "#{@api.class} #{@version}\n" +
      @api.api_methods.map{|c,_|
        ps = @api.method(c).parameters
        data = ps.map{|p| (p[0]==:key && "#{p[1]}=") || (p[0]==:keyrest && "...") || nil}.compact.join('&')
        "#{@api.api_methods[c]} #{c}/" +
          ps.map{|p| (p[0]==:req && "#{p[1]}") || (p[0]==:rest && "...") || nil}.compact.join('/') +
          (data.empty? ? "" : "?#{data}") + "\n"
      }.join
    end
    def call(env)
      req = Request.new env
      h = {"Access-Control-Allow-Origin" => "*"}
      return [HTTP_OK, h.merge({
        "Access-Control-Allow-Headers" => env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'],
        "Access-Control-Allow-Methods" => env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
      }), []] if req.options?
      return [HTTP_NOT_FOUND, h.merge({"Content-Type" => "text/plain"}), [helptext(req)]] if req.cmd == nil
      return [HTTP_NOT_FOUND, h, []] if !@api.api_methods.include?(req.cmd)
      return [HTTP_METHOD_NOT_ALLOWED, h, []] if req.request_method.to_sym != @api.api_methods[req.cmd]
      return Fiber.new do
        Thread.current[:req] = req
        begin
          result = req.named_args.empty? ? @api.public_send(req.cmd, *req.args) : @api.public_send(req.cmd, *req.args, **req.named_args)
          [HTTP_OK, h.merge({"Content-Type" => "text/plain"}), [result.to_s]]
        rescue ArgumentError => e
          [HTTP_BAD_REQUEST, h.merge({"Content-Type" => "text/plain"}), [e.to_s]]
        end
      end.resume
    end
  end
end
