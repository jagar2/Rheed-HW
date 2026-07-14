##Create a script for a multivariable test for synthesis and implementation strategies for Vivado 2016.2
#June 2017 Alberto L. Gasso
#synthesis
create_run synth_5 -flow {Vivado Synthesis 2022} -strategy Flow_AlternateRoutability
create_run synth_7 -flow {Vivado Synthesis 2022} -strategy Flow_PerfThresholdCarry

#Implementation

#synth_5 Flow_AlternateRoutability
create_run imple_135 -parent_run synth_5 -flow {Vivado Implementation 2022} -strategy Performance_NetDelay_low
create_run imple_137 -parent_run synth_5 -flow {Vivado Implementation 2022} -strategy Performance_ExtraTimingOpt
create_run imple_153 -parent_run synth_5 -flow {Vivado Implementation 2022} -strategy Flow_RunPhysOpt
create_run imple_154 -parent_run synth_5 -flow {Vivado Implementation 2022} -strategy Flow_RunPostRoutePhysOpt

#synth_7 Flow_PerfThresholdCarry
create_run imple_205 -parent_run synth_7 -flow {Vivado Implementation 2022} -strategy Performance_NetDelay_low
create_run imple_207 -parent_run synth_7 -flow {Vivado Implementation 2022} -strategy Performance_ExtraTimingOpt
create_run imple_223 -parent_run synth_7 -flow {Vivado Implementation 2022} -strategy Flow_RunPhysOpt
create_run imple_224 -parent_run synth_7 -flow {Vivado Implementation 2022} -strategy Flow_RunPostRoutePhysOpt
