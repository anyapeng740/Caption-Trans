import 'package:equatable/equatable.dart';

class WhisperRuntimeInfo extends Equatable {
  final String modeLabel;
  final String? deviceName;
  final String computeType;
  final int batchSize;
  final bool usingGpu;
  final bool cudaAvailable;
  final String? torchCudaVersion;
  final String? note;

  const WhisperRuntimeInfo({
    required this.modeLabel,
    required this.deviceName,
    required this.computeType,
    required this.batchSize,
    required this.usingGpu,
    required this.cudaAvailable,
    required this.torchCudaVersion,
    this.note,
  });

  String get technicalSummary {
    final List<String> parts = <String>[
      modeLabel,
      if (deviceName != null && deviceName!.trim().isNotEmpty)
        deviceName!.trim(),
      'compute=$computeType',
      'batch=$batchSize',
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
    note,
  ];
}
