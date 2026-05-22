defmodule PostgRESTxn.Metrics do
  @moduledoc """
  Prometheus metric definitions.
  """

  import Telemetry.Metrics

  # FIXME: Suppressing a broken typespec warning.
  # Ref: https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/pull/76
  @dialyzer {:nowarn_function, child_spec: 1}

  @doc false
  def child_spec(_opts) do
    TelemetryMetricsPrometheus.Core.child_spec(metrics: metrics(), start_async: false)
  end

  # Definitions:
  defp metrics do
    [
      counter("postgrestxn.txn.count",
        event_name: [:postgrestxn, :txn, :stop],
        measurement: :duration,
        tags: [:role, :outcome],
        description: "Number of completed transactions."
      ),
      distribution("postgrestxn.txn.duration.milliseconds",
        event_name: [:postgrestxn, :txn, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:role, :outcome],
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000]],
        description: "Transaction duration in milliseconds."
      ),
      counter("postgrestxn.op.count",
        event_name: [:postgrestxn, :op, :stop],
        measurement: :duration,
        tags: [:op, :outcome],
        description: "Number of operations executed within transactions."
      ),
      distribution("postgrestxn.op.duration.milliseconds",
        event_name: [:postgrestxn, :op, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:op, :outcome],
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000]],
        description: "Operation duration in milliseconds."
      ),
      counter("postgrestxn.op.exceptions",
        event_name: [:postgrestxn, :op, :exception],
        measurement: :duration,
        tags: [:op, :table],
        description: "Number of operations that failed with an exception."
      )
    ]
  end
end
