# Java prebuilt coming from Soong.
# Extra inputs:
# LOCAL_SOONG_BUILT_INSTALLED
# LOCAL_SOONG_CLASSES_JAR
# LOCAL_SOONG_HEADER_JAR
# LOCAL_SOONG_DEX_JAR
# LOCAL_SOONG_JACOCO_REPORT_CLASSES_JAR

ifneq ($(LOCAL_MODULE_MAKEFILE),$(SOONG_ANDROID_MK))
  $(call pretty-error,soong_java_prebuilt.mk may only be used from Soong)
endif

LOCAL_MODULE_SUFFIX := .jar
LOCAL_BUILT_MODULE_STEM := javalib.jar

#######################################
include $(BUILD_SYSTEM)/base_rules.mk
#######################################

full_classes_jar := $(intermediates.COMMON)/classes.jar
full_classes_pre_proguard_jar := $(intermediates.COMMON)/classes-pre-proguard.jar
full_classes_header_jar := $(intermediates.COMMON)/classes-header.jar
common_javalib.jar := $(intermediates.COMMON)/javalib.jar
hiddenapi_flags_csv := $(intermediates.COMMON)/hiddenapi/flags.csv
hiddenapi_metadata_csv := $(intermediates.COMMON)/hiddenapi/greylist.csv

$(eval $(call copy-one-file,$(LOCAL_SOONG_CLASSES_JAR),$(full_classes_jar)))
$(eval $(call copy-one-file,$(LOCAL_SOONG_CLASSES_JAR),$(full_classes_pre_proguard_jar)))

ifdef LOCAL_SOONG_JACOCO_REPORT_CLASSES_JAR
  $(eval $(call copy-one-file,$(LOCAL_SOONG_JACOCO_REPORT_CLASSES_JAR),\
    $(intermediates.COMMON)/jacoco-report-classes.jar))
  $(call add-dependency,$(common_javalib.jar),\
    $(intermediates.COMMON)/jacoco-report-classes.jar)
endif

ifdef LOCAL_SOONG_RESOURCE_EXPORT_PACKAGE
  my_res_package := $(intermediates.COMMON)/package-res.apk

  $(my_res_package): $(LOCAL_SOONG_RESOURCE_EXPORT_PACKAGE)
	@echo "Copy: $@"
	$(copy-file-to-target)

  $(call add-dependency,$(LOCAL_BUILT_MODULE),$(my_res_package))

  my_proguard_flags := $(intermediates.COMMON)/export_proguard_flags
  $(my_proguard_flags): $(LOCAL_SOONG_EXPORT_PROGUARD_FLAGS)
	@echo "Export proguard flags: $@"
	rm -f $@
	touch $@
	for f in $+; do \
		echo -e "\n# including $$f" >>$@; \
		cat $$f >>$@; \
	done

  $(call add-dependency,$(LOCAL_BUILT_MODULE),$(my_proguard_flags))

  my_static_library_extra_packages := $(intermediates.COMMON)/extra_packages
  $(eval $(call copy-one-file,$(LOCAL_SOONG_STATIC_LIBRARY_EXTRA_PACKAGES),$(my_static_library_extra_packages)))
  $(call add-dependency,$(LOCAL_BUILT_MODULE),$(my_static_library_extra_packages))

  my_static_library_android_manifest := $(intermediates.COMMON)/manifest/AndroidManifest.xml
  $(eval $(call copy-one-file,$(LOCAL_FULL_MANIFEST_FILE),$(my_static_library_android_manifest)))
  $(call add-dependency,$(LOCAL_BUILT_MODULE),$(my_static_library_android_manifest))
endif # LOCAL_SOONG_RESOURCE_EXPORT_PACKAGE

ifneq ($(TURBINE_ENABLED),false)
ifdef LOCAL_SOONG_HEADER_JAR
$(eval $(call copy-one-file,$(LOCAL_SOONG_HEADER_JAR),$(full_classes_header_jar)))
else
$(eval $(call copy-one-file,$(full_classes_jar),$(full_classes_header_jar)))
endif
endif # TURBINE_ENABLED != false


ifdef LOCAL_SOONG_DEX_JAR
  # Hidden API for boot jars
  ifndef LOCAL_IS_HOST_MODULE
    ifneq ($(filter $(LOCAL_MODULE),$(PRODUCT_BOOT_JARS)),)  # is_boot_jar
      # Derive greylist from classes.jar.
      # We use full_classes_jar here, which is the post-proguard jar (on the basis that we also
      # have a full_classes_pre_proguard_jar). This is consistent with the equivalent code in
      # java.mk.
      $(eval $(call hiddenapi-generate-csv,$(full_classes_jar),$(hiddenapi_flags_csv),$(hiddenapi_metadata_csv)))
      $(eval $(call hiddenapi-copy-soong-jar,$(LOCAL_SOONG_DEX_JAR),$(common_javalib.jar)))
    endif
  endif

  ifneq ($(LOCAL_UNINSTALLABLE_MODULE),true)
    ifndef LOCAL_IS_HOST_MODULE
      ifneq ($(filter $(LOCAL_MODULE),$(PRODUCT_BOOT_JARS)),)  # is_boot_jar
        ifeq (true,$(WITH_DEXPREOPT))
          # For libart, the boot jars' odex files are replaced by $(DEFAULT_DEX_PREOPT_INSTALLED_IMAGE).
          # We use this installed_odex trick to get boot.art installed.
          installed_odex := $(DEFAULT_DEX_PREOPT_INSTALLED_IMAGE)
          # Append the odex for the 2nd arch if we have one.
          installed_odex += $($(TARGET_2ND_ARCH_VAR_PREFIX)DEFAULT_DEX_PREOPT_INSTALLED_IMAGE)
          ALL_MODULES.$(my_register_name).INSTALLED += $(installed_odex)
          # Make sure to install the .odex and .vdex when you run "make <module_name>"
         $(my_all_targets): $(installed_odex)
        endif
      else # !is_boot_jar
        $(eval $(call copy-one-file,$(LOCAL_SOONG_DEX_JAR),$(common_javalib.jar)))
      endif # is_boot_jar
      $(eval $(call add-dependency,$(common_javalib.jar),$(full_classes_jar) $(full_classes_header_jar)))

      $(eval $(call copy-one-file,$(LOCAL_PREBUILT_MODULE_FILE),$(LOCAL_BUILT_MODULE)))
      $(eval $(call add-dependency,$(LOCAL_BUILT_MODULE),$(common_javalib.jar)))
    else # LOCAL_IS_HOST_MODULE
      $(eval $(call copy-one-file,$(LOCAL_SOONG_DEX_JAR),$(LOCAL_BUILT_MODULE)))
      $(eval $(call add-dependency,$(LOCAL_BUILT_MODULE),$(full_classes_jar) $(full_classes_header_jar)))
    endif

    java-dex : $(LOCAL_BUILT_MODULE)
  else  # LOCAL_UNINSTALLABLE_MODULE

    ifneq ($(filter $(LOCAL_MODULE),$(HIDDENAPI_EXTRA_APP_USAGE_JARS)),)
      # Derive greylist from classes.jar.
      # We use full_classes_jar here, which is the post-proguard jar (on the basis that we also
      # have a full_classes_pre_proguard_jar). This is consistent with the equivalent code in
      # java.mk.
      $(eval $(call hiddenapi-generate-csv,$(full_classes_jar),$(hiddenapi_flags_csv),$(hiddenapi_metadata_csv)))
    endif

    $(eval $(call copy-one-file,$(full_classes_jar),$(LOCAL_BUILT_MODULE)))
    $(eval $(call copy-one-file,$(LOCAL_SOONG_DEX_JAR),$(common_javalib.jar)))
    java-dex : $(common_javalib.jar)
  endif  # LOCAL_UNINSTALLABLE_MODULE
else  # LOCAL_SOONG_DEX_JAR
  ifndef LOCAL_UNINSTALLABLE_MODULE
    ifndef LOCAL_IS_HOST_MODULE
      $(call pretty-error,Installable device module must have LOCAL_SOONG_DEX_JAR set)
    endif
  endif
  $(eval $(call copy-one-file,$(full_classes_jar),$(LOCAL_BUILT_MODULE)))
endif  # LOCAL_SOONG_DEX_JAR

my_built_installed := $(foreach f,$(LOCAL_SOONG_BUILT_INSTALLED),\
  $(call word-colon,1,$(f)):$(PRODUCT_OUT)$(call word-colon,2,$(f)))
my_installed := $(call copy-many-files, $(my_built_installed))
ALL_MODULES.$(my_register_name).INSTALLED += $(my_installed)
ALL_MODULES.$(my_register_name).BUILT_INSTALLED += $(my_built_installed)
$(my_register_name): $(my_installed)

ifdef LOCAL_SOONG_AAR
  ALL_MODULES.$(LOCAL_MODULE).AAR := $(LOCAL_SOONG_AAR)
endif

javac-check : $(full_classes_jar)
javac-check-$(LOCAL_MODULE) : $(full_classes_jar)
.PHONY: javac-check-$(LOCAL_MODULE)

ifndef LOCAL_IS_HOST_MODULE
ifeq ($(LOCAL_SDK_VERSION),system_current)
my_link_type := java:system
else ifneq (,$(call has-system-sdk-version,$(LOCAL_SDK_VERSION)))
my_link_type := java:system
else ifeq ($(LOCAL_SDK_VERSION),core_current)
my_link_type := java:core
else ifneq ($(LOCAL_SDK_VERSION),)
my_link_type := java:sdk
else
my_link_type := java:platform
endif
# warn/allowed types are both empty because Soong modules can't depend on
# make-defined modules.
my_warn_types :=
my_allowed_types :=

my_link_deps :=
my_2nd_arch_prefix := $(LOCAL_2ND_ARCH_VAR_PREFIX)
my_common := COMMON
include $(BUILD_SYSTEM)/link_type.mk
endif # !LOCAL_IS_HOST_MODULE

# LOCAL_EXPORT_SDK_LIBRARIES set by soong is written to exported-sdk-libs file
my_exported_sdk_libs_file := $(intermediates.COMMON)/exported-sdk-libs
$(my_exported_sdk_libs_file): PRIVATE_EXPORTED_SDK_LIBS := $(LOCAL_EXPORT_SDK_LIBRARIES)
$(my_exported_sdk_libs_file):
	@echo "Export SDK libs $@"
	$(hide) mkdir -p $(dir $@) && rm -f $@
	$(if $(PRIVATE_EXPORTED_SDK_LIBS),\
		$(hide) echo $(PRIVATE_EXPORTED_SDK_LIBS) | tr ' ' '\n' > $@,\
		$(hide) touch $@)

SOONG_ALREADY_CONV := $(SOONG_ALREADY_CONV) $(LOCAL_MODULE)
