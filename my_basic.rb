require 'rack/auth/abstract/handler'
require 'rack/auth/abstract/request'
require 'rack/auth/basic'


class MyBasic < Rack::Auth::Basic


	SERVICES = [
		["POST", 'service_rpc',      "(.*?)/git-upload-pack$",  'upload-pack'],
		["POST", 'service_rpc',      "(.*?)/git-receive-pack$", 'receive-pack'],
		
		["GET",  'get_info_refs',    "(.*?)/info/refs$"],
		["GET",  'get_text_file',    "(.*?)/HEAD$"],
		["GET",  'get_text_file',    "(.*?)/objects/info/alternates$"],
		["GET",  'get_text_file',    "(.*?)/objects/info/http-alternates$"],
		["GET",  'get_info_packs',   "(.*?)/objects/info/packs$"],
		["GET",  'get_text_file',    "(.*?)/objects/info/[^/]*$"],
		["GET",  'get_loose_object', "(.*?)/objects/[0-9a-f]{2}/[0-9a-f]{38}$"],
		["GET",  'get_pack_file',    "(.*?)/objects/pack/pack-[0-9a-f]{40}\\.pack$"],
		["GET",  'get_idx_file',     "(.*?)/objects/pack/pack-[0-9a-f]{40}\\.idx$"],      
	]



	
	def valid?(auth)
		up = *auth.credentials
		up == [ "tester", "tester" ]
	end

	def call(env)
		
		#require 'dbi'
		#require 'digest/sha1'
		
		@req = Rack::Request.new(env)
      		cmd, path, @reqfile, @rpc = match_routing
		if(cmd != "receive-pack")
		{
			return @app.call(env)
		}




		auth = Request.new(env)
		return unauthorized unless auth.provided?
		return bad_request unless auth.basic?

		if valid?(auth)
			env['REMOTE_USER'] = auth.username
			return @app.call(env)
		end
		unauthorized
	end

	def match_routing
		cmd = nil
		path = nil
		SERVICES.each do |method, handler, match, rpc|
			if m = Regexp.new(match).match(@req.path_info)
				return ['not_allowed'] if method != @req.request_method
				cmd = handler
				path = m[1]
				file = @req.path_info.sub(path + '/', '')
				return [cmd, path, file, rpc]
			end
		end
		return nil
	end


end
