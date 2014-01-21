#
# RackService
#
# An API parent class to make a Ruby object into a web service API for Rack.
#

require 'logger'
require 'rack'
require 'json'

module RackService
  HTTP_METHODS = [:GET, :POST, :PUT, :DELETE]
  HTTP_OK = 200
  HTTP_BAD_REQUEST = 400
  HTTP_NOT_FOUND = 404
  HTTP_METHOD_NOT_ALLOWED = 405
  class Request < Rack::Request
    attr_reader :cmd, :args
    def initialize(env)
      super env
      _, @cmd, *@args = path_info.split('/').map {|e| Rack::Utils::unescape e}
      @cmd = @cmd.to_sym rescue nil
      @args = @args.map{|a| JSON.parse a rescue a}
    end
    def GET; JSON.parse URI.decode_www_form_component query_string rescue super; end
    def POST; media_type == 'application/json' ? JSON.parse((b=body.read;body.rewind;b)) : super; end
    def ignore_params; env['HTTP_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []; end
    def named_args; Hash[params.reject{|k,v| ignore_params.include? k}.map{|k,v| [k.to_sym,v]}]; end
  end
  class API
    def api_methods; self.class.api_instance_methods; end
    HTTP_METHODS.each{|hm| define_method("#{hm.downcase}_methods"){ api_methods.select{|m,h|h==hm}.map{|m,_|m} }}
    def helptext(req)
      @version ||= %x{cd #{File.dirname(caller_locations(1,1)[0].path)}; git describe --match 'v*'}.chomp
      "#{self.class} #{@version}\n" + api_methods.map{|c,_|
        ps = method(c).parameters
        data = ps.map{|p| (p[0]==:key && "#{p[1]}=") || (p[0]==:keyrest && "...") || nil}.compact.join('&')
        "#{api_methods[c]} #{c}/" +
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
      return [HTTP_NOT_FOUND, h, []] if !api_methods.include?(req.cmd)
      return [HTTP_METHOD_NOT_ALLOWED, h, []] if req.request_method.to_sym != api_methods[req.cmd]
      return Fiber.new do
        Thread.current[:rackservice_request] = req
        begin
          result = req.named_args.empty? ? public_send(req.cmd, *req.args) : public_send(req.cmd, *req.args, **req.named_args)
          result_json = result.to_json rescue nil
          [HTTP_OK, *((JSON.parse result_json rescue nil) ? [h.merge({"Content-Type" => "application/json"}), [result_json]] : [h.merge({"Content-Type" => "text/plain"}), [result.to_s]])]
        rescue ArgumentError => e
          [HTTP_BAD_REQUEST, h.merge({"Content-Type" => "text/plain"}), [e.to_s]]
        end
      end.resume
    end
    class << self
      def api_instance_methods; @api_instance_methods ||= {}; end
      def api(http_method, *methods)
        public *methods
        @api_next = http_method if methods.empty?
        methods.each{|m| api_instance_methods[m] = http_method}
      end
      HTTP_METHODS.each{|hm| define_method(hm.downcase){|*methods| api(hm, *methods) }}
      def method_added(m); api(@api_next || HTTP_METHODS.first, m) if public_instance_methods(false).include?(m); end
    end
  end
  LogFormatter = lambda{|_,time,_,msg| req = Thread.current[:rackservice_request]
    "#{time.strftime '%FT%T%z'} #{req.ip} #{[req.referer, req.user_agent].map{|s|(s||'-').inspect}.join(' ')} #{req.cmd} #{msg}\n"
  }
end
