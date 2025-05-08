# /tmp/gitlab_secrets_audit.rb

require 'json'

log_path = "/tmp/gitlab_secrets_audit.log"
json_path = "/tmp/gitlab_secrets_audit_failures.json"

@success_count = 0
@failure_count = 0
@check_count   = 0
@failures = []

def announce(f, message)
  puts "\n#{message}"
  f.puts "\n== #{message} ==\n"
end

def log_success(f, msg)
  f.puts "✅ #{msg}"
  @success_count += 1
  @check_count += 1
end

def log_failure(f, context, msg)
  f.puts "❌ #{context}: #{msg}"

  if context =~ /Deploy Key ID (\d+) – Title: (.+?) – Projects: \[(.+?)\]/
    key_id = $1.to_i
    deploy_key = DeployKey.find_by(id: key_id)
    key_obj = deploy_key&.public_key
    public_key = key_obj.respond_to?(:key) ? key_obj.key.to_s : key_obj.to_s rescue "Unavailable"

    @failures << {
      type: "deploy_key",
      id: key_id,
      title: $2.strip,
      projects: $3.split(", ").map(&:strip),
      error: msg,
      key: public_key
    }
  else
    @failures << {
      type: "generic",
      context: context,
      error: msg
    }
  end

  @failure_count += 1
  @check_count += 1
end

def safe_run(f, label)
  announce(f, "Checking #{label}")
  yield
rescue => e
  log_failure(f, label, "Top-level error: #{e.message}")
end

File.open(log_path, "w") do |f|

  # 1. CI/CD Project Variables
  safe_run(f, "CI/CD Project Variables") do
    Ci::Variable.find_each(batch_size: 1000) do |var|
      begin
        var.value
        project = Project.find_by_id(var.project_id)
        project_path = project&.full_path || "unknown"
        log_success(f, "Project #{project_path} – Key: #{var.key}")
      rescue => e
        log_failure(f, "Var ID #{var.id} (Project ID #{var.project_id})", e.message)
      end
    end
  end

  # 2. Group-Level Variables
  safe_run(f, "Group Variables") do
    Ci::GroupVariable.find_each(batch_size: 1000) do |var|
      begin
        var.value
        group_path = var.group&.full_path || "Unknown group"
        log_success(f, "Group #{group_path} – Key: #{var.key}")
      rescue => e
        group_id = var.group_id || "unknown"
        log_failure(f, "GroupVar ID #{var.id} (Group ID #{group_id})", e.message)
      end
    end
  end

  # 3. Project Runners
  safe_run(f, "Project Runners") do
    Ci::Runner.where(runner_type: :project_type).find_each(batch_size: 100) do |runner|
      begin
        runner.token
        projects = runner.projects.map(&:full_path).join(", ")
        log_success(f, "Project Runner ID #{runner.id} – Projects: [#{projects}]")
      rescue => e
        log_failure(f, "Project Runner ID #{runner.id}", e.message)
      end
    end
  end

  # 4. Group Runners
  safe_run(f, "Group Runners") do
    Ci::Runner.where(runner_type: :group_type).find_each(batch_size: 100) do |runner|
      begin
        runner.token
        log_success(f, "Group Runner ID #{runner.id}")
      rescue => e
        log_failure(f, "Group Runner ID #{runner.id}", e.message)
      end
    end
  end

  # 5. Instance Runners
  safe_run(f, "Instance Runners") do
    Ci::Runner.where(runner_type: :instance_type).find_each(batch_size: 100) do |runner|
      begin
        runner.token
        log_success(f, "Instance Runner ID #{runner.id}")
      rescue => e
        log_failure(f, "Instance Runner ID #{runner.id}", e.message)
      end
    end
  end

  # 6. Kubernetes Integration Tokens
  safe_run(f, "Kubernetes Tokens") do
    Clusters::Platforms::Kubernetes.find_each(batch_size: 100) do |kube|
      begin
        kube.token
        cluster_info = kube.cluster&.name || "Cluster #{kube.cluster_id}"
        log_success(f, "Kubernetes #{cluster_info} – URL: #{kube.api_url}")
      rescue => e
        log_failure(f, "Cluster #{kube.cluster_id}", e.message)
      end
    end
  end

  # 7. Deploy Tokens
  safe_run(f, "Deploy Tokens") do
    DeployToken.find_each(batch_size: 100) do |token|
      begin
        token.token
        associated_projects = token.projects.map(&:full_path).join(", ")
        log_success(f, "Deploy Token ID #{token.id} – Name: #{token.name} – Projects: [#{associated_projects}]")
      rescue => e
        log_failure(f, "Deploy Token ID #{token.id}", e.message)
      end
    end
  end

  # 8. Deploy Keys (with project context)
  safe_run(f, "Deploy Keys") do
    DeployKey.find_each(batch_size: 100) do |key|
      key_obj = key.public_key
      project_paths = key.projects.map(&:full_path).join(", ")
      context = "Deploy Key ID #{key.id} – Title: #{key.title} – Projects: [#{project_paths}]"

      if key_obj.is_a?(SSHData::PublicKey) || key_obj.is_a?(Gitlab::SSHPublicKey)
        log_success(f, context)
      else
        log_failure(f, context, "Unrecognized SSH key object type: #{key_obj.class}")
      end
    end
  end

  # Summary
  announce(f, "Secret Audit Summary")
  summary = <<~SUMMARY
    Total checks: #{@check_count}
    ✅ Successes : #{@success_count}
    ❌ Failures  : #{@failure_count}
  SUMMARY
  puts summary
  f.puts summary

  # Failure Details Report
  unless @failures.empty?
    announce(f, "Detailed Failure Report")
    @failures.each do |failure|
      context = failure[:context] || "Deploy Key ID #{failure[:id]} – Title: #{failure[:title]}" if failure[:type] == "deploy_key"
      puts "❌ #{context}: #{failure[:error]}"
      f.puts "❌ #{context}: #{failure[:error]}"

      if failure[:type] == "deploy_key" && failure[:key]
        truncated_key = failure[:key][0, 40] + "..."
        puts "🔑 Key (truncated): #{truncated_key}"
        f.puts "🔑 Key (truncated): #{truncated_key}"
      end
    end
  end

  # JSON export
if @failures.empty?
  File.delete(json_path) if File.exist?(json_path)
else
  File.write(json_path, JSON.pretty_generate(@failures))
  puts "\n🧾 Failures exported to: #{json_path}"
  f.puts "\n🧾 Failures exported to: #{json_path}"
end
end

puts "\n📄 Secret audit completed. Log saved to: #{log_path}"
