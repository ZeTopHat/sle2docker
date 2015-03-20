module Sle2Docker

  class Template

    def self.list_kiwi
      Dir[File.expand_path('../../templates/kiwi/*', __FILE__)].map do |dir|
        File.basename(dir)
      end
    end

    def self.kiwi_template_dir(template_name)
      dir = File.expand_path("../../templates/kiwi/#{template_name.upcase}", __FILE__)
      if !File.exists?(dir)
        raise TemplateNotFoundError.new("Cannot find template with name #{template_name}")
      end
      dir
    end

  end

end
