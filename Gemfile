source "https://rubygems.org"

#gemspec

group :development do
  # We depend on Vagrant for development, but we don't add it as a
  # gem dependency because we expect to be installed within the
  # Vagrant environment itself using `vagrant plugin`.
  gem "vagrant", :git => "git://github.com/mitchellh/vagrant.git"
  gem "pry-byebug", :path => "/usr/local/lib/ruby/gems/2.3.0/gems/pry-byebug-3.3.0"
end

group :plugins do
  gem "vagrant-xenserver", :path => "."
end
