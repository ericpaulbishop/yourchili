require 'rack/auth/abstract/handler'
require 'rack/auth/abstract/request'
require 'rack/auth/basic'


class RedmineGrackAuth < Rack::Auth::Basic

	DBI_STR="DBI:Mysql:miner_rm:localhost"
	DBI_USER="miner_rm"
	DBI_PASS="password"
	
	def valid?(auth, projName, push, dbh)
		userPass = *auth.credentials
		user = userPass[0]
		pass = userPass[1]

		isValid = false
		begin
			require 'dbi'
			require 'digest/sha1'
			
			# TODO: For now we don't handle alternate auth sources --
			# We assume hashed password is stored in Redmine database
			# At some point alternate auth sources should be implemented

			hashedPass=Digest::SHA1.hexdigest(pass)
			authData = dbh.select_one("SELECT hashed_password, permissions FROM members, projects, users, roles, member_roles WHERE login=\"" + user + "\" AND identifier=\"" + projName + "\" AND projects.id=members.project_id AND member_roles.member_id=members.id AND users.id=members.user_id AND roles.id=member_roles.role_id AND users.status=1")
			
			if(authData.length < 2)
				return false
			end
			
			if(authData[0] == hashedPass)
				if(push && Regexp.new(":commit_access").match(authData[1]))
					isValid=true
				elsif( (not push) && Regexp.new(":commit_access").match(authData[1])) 
					isValid=true
				end
			end
	
		rescue DBI::DatabaseError=>e
			isValid = false
		end
	
		return isValid
	end

	def call(env)
		
		begin
			require 'dbi'
			require 'digest/sha1'

			@env = env	
			@req = Rack::Request.new(env)

			projName = getProjectName()
			dbh = DBI.connect(DBI_STR, DBI_USER, DBI_PASS)
			projRow = dbh.select_one("SELECT is_public FROM projects WHERE name=\"" + projName + "\"")
			
			push = isPush()

			if(projRow.length == 0)
				return unauthorized
			end
			if(projRow[0] == true && (not push))
				return @app.call(env)
			end

		

			auth = Request.new(env)
			return unauthorized unless auth.provided?
			return bad_request unless auth.basic?

			if valid?(auth, projName, push, dbh)
				env['REMOTE_USER'] = auth.username
				return @app.call(env)
			end
			dbh.disconnect;
		
		rescue DBI::DatabaseError=>e
			dbh.disconnect if dbh;
		end

		return unauthorized
	end

	def isPush
		return (@req.request_method == "POST" && Regexp.new("(.*?)/git-receive-pack$").match(@req.path_info) )
	end
	
	def getProjectName
		regexes = ["(.*?)/git-upload-pack$", "(.*?)/git-receive-pack$", "(.*?)/info/refs$", "(.*?)/HEAD$", "(.*?)/objects" ]
		projName = "";
		for re in regexes
			if( m = Regexp.new(re).match(@req.path_info) )
				projPath = m[1];
				projDir  = projPath.gsub(/^.*\//, "")
				projName = projDir.gsub(/\.git$/, "")
			end
		end
		return projName
	end

end
