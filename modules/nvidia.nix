{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Required for the proprietary driver to save/restore GPU state across
    # suspend (installs nvidia-suspend/nvidia-resume systemd services hooked
    # into systemd-suspend.service, and sets NVreg_PreserveVideoMemoryAllocations
    # via modprobe config). Without this, resume from S3 fails with
    # "Flip event timeout" / "invalid mmap context" DRM errors and a dead session.
    powerManagement.enable = true;
  };

  # Wayland/Hyprland on the proprietary driver needs DRM KMS up early.
  # fbdev=1 gives a working framebuffer console on the same device.
  boot.kernelParams = [ "nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" ];

  # Load the nvidia modules in the initrd (not just later in stage 2) so DRM
  # KMS is up before greetd/cage try to grab the display. Without this, the
  # console starts in generic EFI/VESA framebuffer and the nvidia modeset
  # only happens later during systemd userspace boot, racing cage's attempt
  # to acquire DRM master and causing greetd to restart 2-3 times at boot.
  # boot.extraModulePackages (needed so these .ko files are findable from the
  # initrd) is already set by the hardware.nvidia module above since "nvidia"
  # is in services.xserver.videoDrivers -- no separate action needed.
  # nvidia_uvm is deliberately omitted: it's for CUDA/compute, not display,
  # and upstream loads it later via udev+softdep after proper device-node
  # permissions are set up.
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ];

  # GPU-related session variables. This machine exposes a single DRM node
  # (card1 @ 01:00.0, the NVIDIA GPU) with no i915 loaded, so pointing VA-API
  # and GBM at nvidia is unambiguous here.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
