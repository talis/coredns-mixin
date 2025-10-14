local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local var = g.dashboard.variable;
local row = g.panel.row;
local stat = g.panel.stat;
local timeSeries = g.panel.timeSeries;
local prometheus = g.query.prometheus;

{
  grafanaDashboards+:: {
    local datasourceVar =
      var.datasource.new('datasource', 'prometheus')
      + var.datasource.generalOptions.withLabel('Data source'),

    local instanceVar =
      var.query.new('instance')
      + var.query.withDatasourceFromVariable(datasourceVar)
      + var.query.queryTypes.withLabelValues(
        $._config.instanceLabel,
        'coredns_build_info{%(corednsSelector)s}' % $._config,
      )
      + var.query.refresh.onTime()
      + var.query.selectionOptions.withIncludeAll(),

    local instantStat(label, expr, unit='short') =
      stat.new(label)
      + stat.queryOptions.withDatasource('datasource', '$datasource')
      + stat.queryOptions.withTargets([
        prometheus.new('${datasource}', expr)
        + prometheus.withInstant(true)
        + prometheus.withFormat('table'),
      ])
      + stat.standardOptions.color.withMode('fixed')
      + stat.standardOptions.color.withFixedColor('text')
      + stat.standardOptions.withUnit(unit)
      + stat.options.withGraphMode('none'),

    local tsPanel =
      timeSeries {
        new(title):
          timeSeries.new(title)
          + timeSeries.options.legend.withShowLegend()
          + timeSeries.options.legend.withAsTable()
          + timeSeries.options.legend.withDisplayMode('table')
          + timeSeries.options.legend.withPlacement('bottom')
          + timeSeries.options.legend.withCalcs(['min', 'max', 'mean', 'lastNotNull'])
          + timeSeries.options.legend.withSortBy('Max')
          + timeSeries.options.legend.withSortDesc(true)
          + timeSeries.options.tooltip.withMode('multi')
          + timeSeries.fieldConfig.defaults.custom.withShowPoints('never')
          + timeSeries.fieldConfig.defaults.custom.withFillOpacity(10)
          + timeSeries.fieldConfig.defaults.custom.withSpanNulls(true),
      },

    local graphTarget(expr, legend) =
      prometheus.new('${datasource}', expr)
      + prometheus.withLegendFormat(legend)
      + prometheus.withFormat('time_series'),

    local simpleGraph(title, targets, unit='short') =
      tsPanel.new(title)
      + tsPanel.queryOptions.withTargets(targets)
      + tsPanel.standardOptions.withUnit(unit)
      + tsPanel.standardOptions.withMin(0),

    local upCount = instantStat('Up', 'sum(up{%(corednsSelector)s})' % $._config),
    local panicsCount = instantStat('Panics', 'sum(coredns_panics_total{%(corednsSelector)s})' % $._config),

    local rpcRate = simpleGraph('RPC Rate', [
      graphTarget('sum(rate(coredns_dns_responses_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (rcode)' % $._config, '{{rcode}}'),
      graphTarget('sum(rate(coredns_forward_responses_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (rcode)' % $._config, 'forward {{rcode}}'),
    ], 'ops'),

    local requestDuration = simpleGraph('Request duration 99th quantile', [
      graphTarget('histogram_quantile(0.99, sum(rate(coredns_dns_request_duration_seconds_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (server, zone, le))' % $._config, '{{server}} {{zone}}'),
      graphTarget('histogram_quantile(0.99, sum(rate(coredns_forward_request_duration_seconds_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (to, le))' % $._config, 'forward {{to}}'),
    ], 's'),

    local typeRate = simpleGraph('Requests (by qtype)', [
      graphTarget('sum(rate(coredns_dns_requests_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (type)' % $._config, '{{type}}'),
    ], 'ops'),

    local zoneRate = simpleGraph('Requests (by zone)', [
      graphTarget('sum(rate(coredns_dns_requests_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (zone)' % $._config, '{{zone}}'),
    ], 'ops'),

    local forwardRate = simpleGraph('Forward Requests (by to)', [
      graphTarget('sum(rate(coredns_forward_requests_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (to)' % $._config, '{{to}}'),
    ], 'ops'),
    local kubernetesDuration = if $._config.kubernetesPlugin then
      simpleGraph('Kubernetes DNS programming duration', [
        graphTarget('histogram_quantile(0.99, sum(rate(coredns_kubernetes_dns_programming_duration_seconds_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (service_kind, le))' % $._config, '99th {{service_kind}}'),
        graphTarget('histogram_quantile(0.50, sum(rate(coredns_kubernetes_dns_programming_duration_seconds_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (service_kind, le))' % $._config, '50th {{service_kind}}'),
      ], 'seconds')
    else
      instantStat('Plugins Enabled', 'count(sum(coredns_plugin_enabled{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}) by (%(pluginNameLabel)s))' % $._config),

    local requestSize = simpleGraph('Request size', [
      graphTarget('histogram_quantile(0.99, sum(rate(coredns_dns_request_size_bytes_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (server, zone, proto, le))' % $._config, '99th {{server}} {{zone}} {{proto}}'),
      graphTarget('histogram_quantile(0.50, sum(rate(coredns_dns_request_size_bytes_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (server, zone, proto, le))' % $._config, '50th {{server}} {{zone}} {{proto}}'),
    ], 'bytes'),

    local responseSize = simpleGraph('Response size', [
      graphTarget('histogram_quantile(0.99, sum(rate(coredns_dns_response_size_bytes_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (server, zone, proto, le))' % $._config, '99th {{server}} {{zone}} {{proto}}'),
      graphTarget('histogram_quantile(0.50, sum(rate(coredns_dns_response_size_bytes_bucket{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (server, zone, proto, le))' % $._config, '50th {{server}} {{zone}} {{proto}}'),
    ], 'bytes'),

    local cachePercentage = instantStat(
      'Cached',
      'sum(coredns_cache_hits_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}) / (sum(coredns_cache_misses_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}) + sum(coredns_cache_hits_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}))' % $._config,
      'percentunit'
    ),

    local cacheRate = simpleGraph('Cache hit Rate', [
      graphTarget('sum(rate(coredns_cache_hits_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])) by (type)' % $._config, '{{type}}'),
      graphTarget('sum(rate(coredns_cache_misses_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m]))' % $._config, 'misses'),
    ], 'ops'),

    local cacheSize = simpleGraph('Cache Size', [
      graphTarget('sum(coredns_cache_entries{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}) by (type)' % $._config, '{{type}}'),
    ], 'short'),

    local memory = simpleGraph('Memory', [
      graphTarget('process_resident_memory_bytes{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}' % $._config, '{{%(instanceLabel)s}}' % $._config),
    ], 'bytes'),

    local cpu = simpleGraph('CPU usage', [
      graphTarget('rate(process_cpu_seconds_total{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}[5m])' % $._config, '{{%(instanceLabel)s}}' % $._config),
    ], 'short'),

    local goroutines = simpleGraph('Goroutines', [
      graphTarget('go_goroutines{%(corednsSelector)s,%(instanceLabel)s=~"$instance"}' % $._config, '{{%(instanceLabel)s}}' % $._config),
    ], 'short'),

    'coredns.json':
      g.dashboard.new('%(dashboardNamePrefix)sCoreDNS' % $._config.grafana)
      + g.dashboard.withUid($._config.grafanaDashboardIDs['coredns.json'])
      + g.dashboard.withTags(($._config.grafana.dashboardTags))
      + g.dashboard.time.withFrom('now-1h')
      + g.dashboard.time.withTo('now')
      + g.dashboard.withVariables([
        datasourceVar,
        instanceVar,
      ])
      + g.dashboard.withPanels(
        g.util.grid.wrapPanels([
          upCount + row.gridPos.withW(2),
          panicsCount + row.gridPos.withW(2),
          rpcRate + row.gridPos.withW(10),
          requestDuration + row.gridPos.withW(10),

          typeRate,
          zoneRate,
          forwardRate,

          cachePercentage + row.gridPos.withW(4),
          cacheRate + row.gridPos.withW(10),
          cacheSize + row.gridPos.withW(10),

          kubernetesDuration + row.gridPos.withW(if $._config.kubernetesPlugin then 8 else 4),
          requestSize + row.gridPos.withW(if $._config.kubernetesPlugin then 8 else 10),
          responseSize + row.gridPos.withW(if $._config.kubernetesPlugin then 8 else 10),

          memory,
          cpu,
          goroutines,
        ], 8, 7),
      )
      + { refresh: $._config.grafana.refresh },
  },
}
