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

require 'kitchen'
require 'kitchen/configurable'
require_relative 'cli_helper'
require_relative 'container_helper'

module Kitchen
  module Docker
    module Helpers
      module ImageHelper
        include Configurable
        include Kitchen::Docker::Helpers::CliHelper
        include Kitchen::Docker::Helpers::ContainerHelper

        def parse_image_id(output)
          docker_version = `docker info | grep 'Server Version'`.split(' ').last

          output.each_line do |line|
            case docker_version
            when /^20/
              if line =~ /sha256/
                return line.split(/\s+/).last
              end
            else
              if line =~ /image id|build successful|successfully built/i
                return line.split(/\s+/).last
              end
            end
          end
          raise ActionFailed, 'Could not parse Docker build output for image ID'
        end

        def remove_image(state)
          image_id = state[:image_id]
          docker_command("rmi #{image_id}")
        end

        def build_image(state, dockerfile)
          docker_version = `docker info | grep 'Server Version'`.split(' ').last

          cmd = 'build'
          cmd << ' --no-cache' unless config[:use_cache]

          if docker_version =~ /^20/
            cmd << ' -q'
          end

          extra_build_options = config_to_options(config[:build_options])
          cmd << " #{extra_build_options}" unless extra_build_options.empty?
          dockerfile_contents = dockerfile
          build_context = config[:build_context] ? '.' : '-'
          file = Tempfile.new('Dockerfile-kitchen', Dir.pwd)
          output = begin
                     file.write(dockerfile)
                     file.close
                     docker_command("#{cmd} -f #{Shellwords.escape(dockerfile_path(file))} #{build_context}",
                                    input: dockerfile_contents,
                                    environment: { DOCKER_BUILDKIT: '0' })
                   ensure
                     file.close unless file.closed?
                     file.unlink
                   end

          parse_image_id(output)
        end

        def image_exists?(state)
          state[:image_id] && !!docker_command("inspect --type=image #{state[:image_id]}") rescue false
        end
      end
    end
  end
end
