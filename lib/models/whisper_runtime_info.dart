import 'package:equatable/equatable.dart';

class WhisperRuntimeInfo extends Equatable {
  final String modeLabel;
  final String? deviceName;
  final String computeType;
  final int batchSize;
  final bool usingGpu;
  final bool cudaAvailable;
  final String? torchCudaVersion;
  final int? logicalCpuCount;
  final int? physicalCpuCount;
  final int? recommendedCpuThreads;
  final String? note;

  const WhisperRuntimeInfo({
    required this.modeLabel,
    required this.deviceName,
    required this.computeType,
    required this.batchSize,
    required this.usingGpu,
    required this.cudaAvailable,
    required this.torchCudaVersion,
    required this.logicalCpuCount,
    required this.physicalCpuCount,
    required this.recommendedCpuThreads,
    this.note,
  });

  String get technicalSummary {
    final List<String> parts = <String>[
      modeLabel,
      if (deviceName != null && deviceName!.trim().isNotEmpty)
        deviceName!.trim(),
      'compute=$computeType',
      'batch=$batchSize',
      if (physicalCpuCount != null) 'physical CPU $physicalCpuCount',
      if (logicalCpuCount != null) 'logical CPU $logicalCpuCount',
      if (recommendedCpuThreads != null) 'threads=$recommendedCpuThreads',
      if (torchCudaVersion != null && torchCudaVersion!.trim().isNotEmpty)
        'torch CUDA ${torchCudaVersion!.trim()}',
    ];
    return parts.join(' | ');
  }

  @override
  List<Object?> get props => <Object?>[
    modeLabel,
    deviceName,
    computeType,
    batchSize,
    usingGpu,
    cudaAvailable,
    torchCudaVersion,
    logicalCpuCount,
    physicalCpuCount,
    recommendedCpuThreads,
    note,
  ];
}
