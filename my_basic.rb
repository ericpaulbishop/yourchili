require 'rack/auth/abstract/handler'
require 'rack/auth/abstract/request'
require 'rack/auth/basic'


class MyBasic < Rack::Auth::Basic
	
	#def my_authenticator(user, pass)
	#	[user, pass] == [ "tester", "tester" ]
	#end
	
	def valid?(auth)
		up = *auth.credentials
		up == [ "tester", "tester" ]
	end

	def call(env)
		
		#return @app.call(env)

		auth = Request.new(env)
		return unauthorized unless auth.provided?
		return bad_request unless auth.basic?

		if valid?(auth)
			env['REMOTE_USER'] = auth.username
			return @app.call(env)
		end
		unauthorized
	end
end
