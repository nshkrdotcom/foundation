# Code formatting configuration for Foundation layer
[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "scripts/**/*.{ex,exs}",
    "mix.exs"
  ],
  line_length: 100,
  locals_without_parens: [
    # ExUnit
    assert: 1,
    assert: 2,
    refute: 1,
    refute: 2,

    # Custom DSL (if any)
  ]
]
