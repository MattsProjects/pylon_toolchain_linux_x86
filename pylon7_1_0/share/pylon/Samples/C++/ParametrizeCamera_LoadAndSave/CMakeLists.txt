add_executable( ParametrizeCamera_LoadAndSave ParametrizeCamera_LoadAndSave.cpp)
target_link_libraries( ParametrizeCamera_LoadAndSave PRIVATE pylon::pylon )
install( TARGETS ParametrizeCamera_LoadAndSave )