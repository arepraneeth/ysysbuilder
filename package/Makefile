ifndef RELEASE
RELEASE=test
endif

all:: ysysbuilder

ysysbuilder: perl-test
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ysysbuilder.yicf --platform rhel

ysysbuilder_build:
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ysysbuilder_build.yicf --platform rhel

perl-test:
	cover -delete
	../t/run-tests
	../t/compile-steps
	cd ../t && cover
	cd ../t && cover2clover.pl -coverdb cover_db


test:: ysysbuilder/test

tags:
	cd ..; etags --language=perl `find t lib -type f ! -path '*/CVS/*' ! -path '*~*' ! -path '*/files/*'`

installer:
	../bin/create_installer --name=rhel --steps=std-rhel --out=`pwd`
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ybootserver_installer_rhel.yicf --platform rhel
	../bin/create_installer --name=windows --steps=std-windows --out=`pwd`
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ybootserver_installer_windows.yicf --platform rhel
	../bin/create_installer --name=firmware --steps=std-firmware --out=`pwd`
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ybootserver_installer_firmware.yicf --platform rhel
	../bin/create_installer --name=burnin --steps=burnin --out=`pwd`
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ybootserver_installer_burnin.yicf --platform rhel
	../bin/create_installer --name=wipedrives --steps=wipe_drives --out=`pwd`
	yinst_create --buildtype=$(RELEASE) $(CREATE_ARGS) ybootserver_installer_wipedrives.yicf --platform rhel

%/test:
	$(MAKE) $* $(MAKEFILEARG) RELEASE=test

%/install:
	$(MAKE) $* $(MAKEFILEARG) CREATE_ARGS='--install $(INSTALL_ARGS)'

clean:
	rm -f *.tgz
	rm -f *.tar.gz
	rm -fr *.package
	rm -fr ../t/cover_db ../t/clover-reports

.PHONY : tags ysysbuilder ysysbuilder_build
