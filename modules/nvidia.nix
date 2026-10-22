{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Wayland/Hyprland on the proprietary driver needs DRM KMS up early.
  # fbdev=1 gives a working framebuffer console on the same device.
  boot.kernelParams = [ "nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" ];

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
