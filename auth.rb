def do_redmine_auth(env)
	
	valid = false
	use Rack::Auth::Basic do |user,pass|
		outfile= File.open("/tmp/rdbi_test.txt", "w")
		begin
			require 'dbi'
			require 'digest/sha1'
			hashedProvidedPass=Digest::SHA1.hexdigest(pass)

                        if(defined?(env))
				outfile.puts "env_exists"
			else
				outfile.puts "no env"
			end


			dbh = DBI.connect("DBI:Mysql:miner_rm:localhost", "miner_rm", "password")
			userRow = dbh.select_one("SELECT hashed_password FROM users WHERE login=\"" + user + "\"")

			@req = Rack::Request.new(env)
			outfile.puts @req.request_method  
			#outfile.puts " ook "		
	
			if ( defined?(userRow) )
				if (defined?(userRow[0]))
					outfile.puts userRow[0]
					valid = hashedProvidedPass == userRow[0] ? true : false;
				end
			end

		rescue Error => e
			outfile.puts "Error message: #{e.errstr}"
		ensure
			dbh.disconnect if dbh
		end
		outfile.close

		valid
	end

end


