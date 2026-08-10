repo_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("..", repo_root)

dep = fn repository, subdir ->
  %{
    path: Path.join(siblings_root, "#{repository}/#{subdir}"),
    github: %{repo: "nshkrdotcom/#{repository}", branch: "main", subdir: subdir},
    hex: "~> 0.1.0",
    default_order: [:path, :github, :hex],
    publish_order: [:hex]
  }
end

%{
  deps: %{
    app_kit_budget_surface: dep.("app_kit", "core/budget_surface"),
    app_kit_context_budget_surface: dep.("app_kit", "core/context_budget_surface"),
    app_kit_coordination_surface: dep.("app_kit", "core/coordination_surface"),
    app_kit_core: dep.("app_kit", "core/app_kit_core"),
    app_kit_cost_surface: dep.("app_kit", "core/cost_surface"),
    app_kit_hive_surface: dep.("app_kit", "core/hive_surface"),
    app_kit_memory_surface: dep.("app_kit", "core/memory_surface"),
    app_kit_model_surface: dep.("app_kit", "core/model_surface"),
    app_kit_operator_surface: dep.("app_kit", "core/operator_surface"),
    app_kit_replay_surface: dep.("app_kit", "core/replay_surface"),
    app_kit_review_surface: dep.("app_kit", "core/review_surface"),
    app_kit_skill_surface: dep.("app_kit", "core/skill_surface"),
    mezzanine_pack_model: dep.("mezzanine", "core/pack_model")
  }
}