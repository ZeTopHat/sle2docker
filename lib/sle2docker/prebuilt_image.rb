module Sle2Docker
  # This class takes care of handling the pre-build images for
  # SUSE Linux Enterprise
  class PrebuiltImage
    IMAGES_DIR = '/usr/share/suse-docker-images'.freeze
    DOCKERFILE_TEMPLATE = File.join(
      File.expand_path('../../templates/docker_build', __FILE__),
      'dockerfile.erb'
    )

    attr_reader :image_id

    def self.list
      if File.exist?(PrebuiltImage::IMAGES_DIR)
        Dir[File.join(IMAGES_DIR, '*.tar.xz')].map do |image|
          File.basename(image, '.tar.xz')
        end
      else
        []
      end
    end

    def initialize(image_name, options)
      @image_name = image_name
      @options    = options
      compute_repository_and_tag
    end

    def activated?
      Docker::Image.exist?(image_id)
    end

    def activate
      verify_image

      tmp_dir = prepare_docker_build_root
      puts 'Activating image'
      image = Docker::Image.build_from_dir(tmp_dir)
      image.tag('repo' =>  @repository, 'tag' => @tag)
      image.tag('repo' =>  @repository, 'tag' => 'latest')
    ensure
      FileUtils.rm_rf(tmp_dir) if tmp_dir && File.exist?(tmp_dir)
    end

    def prepare_docker_build_root
      tmp_dir = Dir.mktmpdir("sle2docker-#{@image_name}-dockerfile")

      create_dockerfile(tmp_dir)
      copy_prebuilt_image(tmp_dir)
      tmp_dir
    end

    def create_dockerfile(tmp_dir)
      prebuilt_image = @image_name + '.tar.xz'

      template = ERB.new(File.read(DOCKERFILE_TEMPLATE), nil, '<>')
                    .result(binding)

      File.open(File.join(tmp_dir, 'Dockerfile'), 'w') do |file|
        file.write(template)
      end
    end

    def copy_prebuilt_image(tmp_dir)
      prebuilt_image = File.join(IMAGES_DIR, "#{@image_name}.tar.xz")
      destination = File.join(tmp_dir, "#{@image_name}.tar.xz")
      FileUtils.cp(prebuilt_image, destination)
    end

    def rpm_package_name
      file = File.join(IMAGES_DIR, "#{@image_name}.tar.xz")
      package_name = `rpm -qf #{file}`
      if $CHILD_STATUS.exitstatus.nonzero?
        raise(
          PrebuiltImageVerificationError,
          "Cannot find rpm package providing #{file}: #{package_name}"
        )
      end
      package_name
    end

    def check_image_exists
      msg = "Cannot find pre-built image #{@image_name}"
      raise(
        PrebuiltImageNotFoundError, msg
      ) unless File.exist?(
        File.join(IMAGES_DIR, "#{@image_name}.tar.xz")
      )
    end

    def verify_image
      check_image_exists

      puts 'Verifying integrity of the pre-built image'
      package_name = rpm_package_name
      verification = `rpm --verify #{package_name}`
      raise(
        PrebuiltImageVerificationError,
        "Verification of #{package_name} failed: #{verification}"
      ) if $CHILD_STATUS.exitstatus.nonzero?
      true
    end

    private

    def compute_repository_and_tag
      # example of image name: sles12-docker.x86_64-1.0.0-Build7.2
      regexp = /\A(?<name>.*)-docker\..*-(?<version>\d+\.\d+\.\d+)
       (-Build(?<build>\d+\.\d+)?)?/x
      match = regexp.match(@image_name)
      match.nil? &&
        raise(DockerTagError,
              "Docker image #{@image_name} not found. \
               Run sle2docker list to check which docker images are available.")

      @repository = "suse/#{match['name']}"
      @tag        = match['version']
      @options['tag_with_build'] && @tag << '-' + (match['build'] || '0.0')
      @image_id = "#{@repository}:#{@tag}"
    end
  end
end
