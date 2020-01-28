#
# Author:: Joshua Timberman <joshua@chef.io>
# Copyright:: Copyright (c) 2013-2015, Chef Software, Inc. <legal@chef.io>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/version_constraint'
require 'chef/util/path_helper'
require 'uri'
require 'pathname'

module ChefCookbook
  class OpenJDK
    attr_accessor :java_home, :jdk_version

    def initialize(node)
      @node = node.to_hash
      @java_home = @node['java']['java_home'] || '/usr/lib/jvm/default-java'
      @jdk_version = @node['java']['jdk_version'].to_s || '6'
    end

    def java_location
      File.join(java_home_parent(@java_home), openjdk_path, 'bin/java')
    end

    def java_home_parent(java_home)
      Pathname.new(java_home).parent.to_s
    end

    def openjdk_path
      case @node['platform_family']
      when 'debian'
        format('java-%s-openjdk%s/jre', @jdk_version, arch_dir)
      when 'rhel', 'fedora', 'amazon'
        path = @node['java']['jdk_version'].to_i < 11 ? 'jre-1.%s.0-openjdk%s' : 'java-%s'
        format(path, @jdk_version, arch_dir)
      else
        'jre'
      end
    end

    def arch_dir
      @node['kernel']['machine'] == 'x86_64' ? sixty_four : thirty_two
    end

    def sixty_four
      case @node['platform_family']
      when 'debian'
        '-amd64'
      when 'rhel', 'fedora', 'amazon'
        '.x86_64'
      else
        '-x86_64'
      end
    end

    def thirty_two
      case @node['platform_family']
      when 'debian'
        '-i386'
      else
        ''
      end
    end
  end
end

class Chef
  class Recipe
    def valid_ibm_jdk_uri?(url)
      url =~ ::URI::ABS_URI && %w(file http https).include?(::URI.parse(url).scheme)
    end

    def platform_requires_license_acceptance?
      %w(smartos).include?(node['platform'])
    end

    def find_java(java_home=nil, version=nil)
      # java_home - given JAVA_HOME to check version
      # version - major JAVA version, e.g. '1.8.0_232' -> 8
      if node['platform'] == 'windows'
        existence_check = :exists?
        which = 'where'
        java_in_path = java_home ? "#{java_home}\\bin:java.exe" : "java.exe"
      else
        existence_check = :executable?
        which = 'which'
        java_in_path = java_home ? "#{java_home}/bin/java" : "java"
      end

      Chef::Log.debug "Using '#{which}' in #{java_in_path} to check the Java binary"

      # check all executables for version
      shell_out("#{which} #{java_in_path}").stdout.chomp.split(/\n+/).each do |p|
        p = "\"#{p}\"" if ['windows'].include?(node['platform'])
        if version
          if shell_out("#{p} -version").stderr.chomp =~ /^([^ ]+) version "(\d+)\.(\d+)\.(.*)"/m
            jdk = $1
            ver = $2
            rel = $3
            subver = $4
            Chef::Log.debug "Found JDK: #{jdk} version #{ver}.#{rel}.#{subver} for node['jdk_version'] = #{version}"
            return p if version && version == rel
          end
        else
          return p
        end
      end
      false
    end

  end
end
