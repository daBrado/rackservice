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

HTTP_METHODS = [:GET, :POST, :PUT, :DELETE]

class APIApp
  def initialize(api, *api_args, log:Logger.new(STDERR), **api_named_args)
    @log = log
    @log.formatter = lambda{|_,time,_,msg|
      req, cmd = Thread.current[:loginfo]
      "#{time.strftime '%FT%T%z'} #{req.ip} #{[req.referer, req.user_agent].map{|s|(s||'-').inspect}.join(' ')} #{cmd} #{msg}\n"
    }
    @api = api.new(*api_args, log: log, **api_named_args)
    @version = %x{cd #{File.dirname(caller_locations(1,1)[0].path)}; git describe --match 'v*'}.chomp
  end
  def cmds
    (HTTP_METHODS & @api.class.constants).flat_map{|m| @api.class.const_get(m)} & @api.methods
  end
  def cmd_method(cmd)
    (@api.class.constants & HTTP_METHODS).reduce{|memo,http_method| @api.class.const_get(http_method).include?(cmd) ? http_method : memo}
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
      cmd = cmd.to_sym rescue nil
      ignore_params = env['HTTP_X_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []
      named_args = Hash[req.params.reject{|k,v| ignore_params.include? k}.map{|k,v| [k.to_sym,v]}]
      [cmd, args, named_args]
    )
    if cmd == nil
      [HTTP_NOT_FOUND, h.merge({"Content-Type" => "text/plain"}), [
        "#{req.url} #{@api.class} #{@version}\n",
        cmds.map{|c|
          ps = @api.method(c).parameters
          data = ps.map{|p| (p[0]==:key && "#{p[1]}=") || (p[0]==:keyrest && "...") || nil}.compact.join('&')
          "#{cmd_method(c)} #{c}/" +
            ps.map{|p| (p[0]==:req && "#{p[1]}") || (p[0]==:rest && "...") || nil}.compact.join('/') +
            (data.empty? ? "" : "?#{data}") + "\n"
        }.join
      ]]
    else
      return [HTTP_NOT_FOUND, h, []] if !cmds.include?(cmd)
      return [HTTP_METHOD_NOT_ALLOWED, h, []] if req.request_method.to_sym != cmd_method(cmd)
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
end
