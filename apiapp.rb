#
# API App
#
# A Rack application to use a Ruby object as a web API.
#

require 'logger'
require 'rack'

HTTP_OK = 200
HTTP_BAD_REQUEST = 400
HTTP_NOT_FOUND = 404
HTTP_METHOD_NOT_ALLOWED = 405

class APIApp
  def initialize(api, *api_args, log:Logger.new(STDERR), **api_named_args)
    @log = log
    @log.formatter = lambda{|_,time,_,msg|
      req, cmd = Thread.current[:loginfo]
      "#{time.strftime '%FT%T%z'} #{req.ip} #{[req.referer, req.user_agent].map{|s|(s||'-').inspect}.join(' ')} #{cmd} #{msg}\n"
    }
    @api = api.new(*api_args, log: log, **api_named_args)
  end
  def call(env)
    req = Rack::Request.new env
    h = {"Access-Control-Allow-Origin" => "*"}
    return [HTTP_OK, h.merge({
      "Access-Control-Allow-Headers" => env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'],
      "Access-Control-Allow-Methods" => env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
    }), []] if req.options?
    cmd, args, named_args = (
      _, cmd, *args = req.path_info.split('/').map {|e| Rack::Utils::unescape e}
      cmd = cmd.to_sym rescue :''
      ignore_params = env['HTTP_X_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []
      named_args = Hash[req.params.reject{|k,v| ignore_params.include? k}.map{|k,v| [k.to_sym,v]}]
      [cmd, args, named_args]
    )
    return [HTTP_NOT_FOUND, h, []] if !@api.class.public_method_defined?(cmd)
    return [HTTP_METHOD_NOT_ALLOWED, h, []] if !(@api.class.const_get(req.request_method.to_sym).include?(cmd) rescue false)
    Fiber.new do
      Thread.current[:loginfo] = [req, cmd]
      begin
        result = named_args.empty? ? @api.public_send(cmd, *args) : @api.public_send(cmd, *args, **named_args)
        [HTTP_OK, h.merge({"Content-Type" => "text/plain"}), [result.to_s]]
      rescue ArgumentError => e
        [HTTP_BAD_REQUEST, h.merge({"Content-Type" => "text/plain"}), [e.to_s]]
      end
    end.resume
  end
end
