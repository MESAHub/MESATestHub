# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)
version_created = Version.find_or_create_by(number: 10000)
TEST_CASES = TestCase.create!(
  [
    {
      name: 'double_bh',
      version_id: version_created.id
    },
    {
      name: 'jdot_ls_check',
      version_id: version_created.id
    },
    {
      name: 'jdot_gr_check',
      version_id: version_created.id
    },
    {
      name: 'jdot_ml_check',
      version_id: version_created.id
    },
    {
      name: 'evolve_both_stars',
      version_id: version_created.id
    },
    {
      name: 'star_plus_point_mass_explicit_mdot',
      version_id: version_created.id
    },
    {
      name: 'star_plus_point_mass',
      version_id: version_created.id
    },
    {
      name: 'wd_surf_at_tau_1m4',
      version_id: version_created.id
    },
    {
      name: 'wd_ignite',
      version_id: version_created.id
    },
    {
      name: 'wd_diffusion',
      version_id: version_created.id
    },
    {
      name: 'wd_cool_0.6M',
      version_id: version_created.id
    },
    {
      name: 'wd_aic',
      version_id: version_created.id
    },
    {
      name: 'wd_acc_small_dm',
      version_id: version_created.id
    },
    {
      name: 'wd3',
      version_id: version_created.id
    },
    {
      name: 'wd2',
      version_id: version_created.id
    },
    {
      name: 'wd',
      version_id: version_created.id
    },
    {
      name: 'very_low_mass',
      version_id: version_created.id
    },
    {
      name: 'timing',
      version_id: version_created.id
    },
    {
      name: 'surface_effects',
      version_id: version_created.id
    },
    {
      name: 'split_burn_big_net_30M_logT_9.8',
      version_id: version_created.id
    },
    {
      name: 'split_burn_big_net_30M',
      version_id: version_created.id
    },
    {
      name: 'split_burn_20M_si_burn_qp',
      version_id: version_created.id
    },
    {
      name: 'simplex_solar_calibration',
      version_id: version_created.id
    },
    {
      name: 'sewind',
      version_id: version_created.id
    },
    {
      name: 'semiconvection',
      version_id: version_created.id
    },
    {
      name: 'sedov_omega_1',
      version_id: version_created.id
    },
    {
      name: 'sample_pre_ms',
      version_id: version_created.id
    },
    {
      name: 'sample_he_zams',
      version_id: version_created.id
    },
    {
      name: 'rsp_save_and_load_file',
      version_id: version_created.id
    },
    {
      name: 'rsp_gyre',
      version_id: version_created.id
    },
    {
      name: 'rsp_check_2nd_crossing',
      version_id: version_created.id
    },
    {
      name: 'rsp_Type_II_Cepheid',
      version_id: version_created.id
    },
    {
      name: 'rsp_RR_Lyrae',
      version_id: version_created.id
    },
    {
      name: 'rsp_Delta_Scuti',
      version_id: version_created.id
    },
    {
      name: 'rsp_Cepheid',
      version_id: version_created.id
    },
    {
      name: 'rsp_BLAP',
      version_id: version_created.id
    },
    {
      name: 'rsp_BEP',
      version_id: version_created.id
    },
    {
      name: 'relax_composition_j_entropy',
      version_id: version_created.id
    },
    {
      name: 'radiative_levitation',
      version_id: version_created.id
    },
    {
      name: 'pre_zahb',
      version_id: version_created.id
    },
    {
      name: 'ppisn',
      version_id: version_created.id
    },
    {
      name: 'other_physics_hooks',
      version_id: version_created.id
    },
    {
      name: 'ns_he',
      version_id: version_created.id
    },
    {
      name: 'ns_h',
      version_id: version_created.id
    },
    {
      name: 'ns_c',
      version_id: version_created.id
    },
    {
      name: 'nova',
      version_id: version_created.id
    },
    {
      name: 'noh_riemann',
      version_id: version_created.id
    },
    {
      name: 'neutron_star_envelope',
      version_id: version_created.id
    },
    {
      name: 'multiple_stars',
      version_id: version_created.id
    },
    {
      name: 'multimass',
      version_id: version_created.id
    },
    {
      name: 'make_sdb',
      version_id: version_created.id
    },
    {
      name: 'make_planets',
      version_id: version_created.id
    },
    {
      name: 'make_o_ne_wd',
      version_id: version_created.id
    },
    {
      name: 'make_metals',
      version_id: version_created.id
    },
    {
      name: 'make_he_wd',
      version_id: version_created.id
    },
    {
      name: 'make_co_wd',
      version_id: version_created.id
    },
    {
      name: 'make_brown_dwarf',
      version_id: version_created.id
    },
    {
      name: 'magnetic_braking',
      version_id: version_created.id
    },
    {
      name: 'low_z',
      version_id: version_created.id
    },
    {
      name: 'irradiated_planet',
      version_id: version_created.id
    },
    {
      name: 'hydro_Ttau_solar',
      version_id: version_created.id
    },
    {
      name: 'hydro_Ttau_evolve',
      version_id: version_created.id
    },
    {
      name: 'hse_riemann',
      version_id: version_created.id
    },
    {
      name: 'hot_cool_wind',
      version_id: version_created.id
    },
    {
      name: 'high_rot_darkening',
      version_id: version_created.id
    },
    {
      name: 'high_z',
      version_id: version_created.id
    },
    {
      name: 'high_mass',
      version_id: version_created.id
    },
    {
      name: 'he_core_flash',
      version_id: version_created.id
    },
    {
      name: 'hb_2M',
      version_id: version_created.id
    },
    {
      name: 'gyre_in_mesa_wd',
      version_id: version_created.id
    },
    {
      name: 'gyre_in_mesa_spb',
      version_id: version_created.id
    },
    {
      name: 'gyre_in_mesa_rsg',
      version_id: version_created.id
    },
    {
      name: 'gyre_in_mesa_ms',
      version_id: version_created.id
    },
    {
      name: 'gyre_in_mesa_bcep',
      version_id: version_created.id
    },
    {
      name: 'example_make_pre_ccsn',
      version_id: version_created.id
    },
    {
      name: 'example_ccsn_IIp',
      version_id: version_created.id
    },
    {
      name: 'example_astero',
      version_id: version_created.id
    },
    {
      name: 'envelope_inflation',
      version_id: version_created.id
    },
    {
      name: 'diffusion_smoothness',
      version_id: version_created.id
    },
    {
      name: 'det_riemann',
      version_id: version_created.id
    },
    {
      name: 'custom_rates',
      version_id: version_created.id
    },
    {
      name: 'custom_colors',
      version_id: version_created.id
    },
    {
      name: 'create_zams',
      version_id: version_created.id
    },
    {
      name: 'conserve_angular_momentum',
      version_id: version_created.id
    },
    {
      name: 'conductive_flame',
      version_id: version_created.id
    },
    {
      name: 'cburn_inward',
      version_id: version_created.id
    },
    {
      name: 'c13_pocket',
      version_id: version_created.id
    },
    {
      name: 'brown_dwarf',
      version_id: version_created.id
    },
    {
      name: 'black_hole',
      version_id: version_created.id
    },
    {
      name: 'axion_cooling',
      version_id: version_created.id
    },
    {
      name: 'astero_gyre',
      version_id: version_created.id
    },
    {
      name: 'astero_adipls',
      version_id: version_created.id
    },
    {
      name: 'agb_to_wd',
      version_id: version_created.id
    },
    {
      name: 'agb',
      version_id: version_created.id
    },
    {
      name: 'adjust_net',
      version_id: version_created.id
    },
    {
      name: 'accretion_with_diffusion',
      version_id: version_created.id
    },
    {
      name: 'accreted_material_j',
      version_id: version_created.id
    },
    {
      name: '8.8M_urca',
      version_id: version_created.id
    },
    {
      name: '7M_prems_to_AGB',
      version_id: version_created.id
    },
    {
      name: '5M_cepheid_blue_loop',
      version_id: version_created.id
    },
    {
      name: '25M_z2m2_high_rotation',
      version_id: version_created.id
    },
    {
      name: '25M_pre_ms_to_core_collapse',
      version_id: version_created.id
    },
    {
      name: '1M_thermohaline_split_mix',
      version_id: version_created.id
    },
    {
      name: '1M_thermohaline',
      version_id: version_created.id
    },
    {
      name: '1M_pre_ms_to_wd',
      version_id: version_created.id
    },
    {
      name: '16M_predictive_mix',
      version_id: version_created.id
    },
    {
      name: '15M_dynamo',
      version_id: version_created.id
    },
    {
      name: '1.5M_with_diffusion',
      version_id: version_created.id
    },
    {
      name: '1.4M_ms_op_mono',
      version_id: version_created.id
    },
    {
      name: '1.3M_ms_high_Z',
      version_id: version_created.id
    },
    {
      name: 'wd_cool',
      version_id: version_created.id
    }
  ]
)



USERS = User.create!(
  (1..6).to_a.map do |i|
    first_name = Faker::Name.unique.first_name
    {
      email: Faker::Internet.free_email(first_name),
      password: 'password',
      name: first_name + ' ' + Faker::Name.unique.last_name,
      admin: true
    }
  end
)

PROCESSORS = [
  "3.6 GHz 8-core Intel Xeon E3-1271",
  "3.4 GHz 8-core Intel i7-4770",
  "2.7 GHz 12-Core Intel Xeon E5",
  "2.40GHz Intel Xeon E5620",
  "AMD FX(tm)-8350 Eight-Core Processor",
  "Intel(R) Xeon(R) CPU E5-2640 v4 @ 2.40GHz",
  "4.2 GHz 6-Core Intel i7",
  "2.9 GHz 4-Core Intel i5",
  "3.6 Ghz 8 core Ryzen 7 1800X",
  "AMD Ryzen 5 2600"
]

COMPUTERS = Computer.create!(
  (1..12).to_a.map do |i|
    {
      name: Faker::GreekPhilosophers.unique.name, 
      user: USERS.sample,
      platform: ['macOS', 'linux'].sample,
      processor: PROCESSORS.sample,
      ram_gb: [16, 16, 16, 32, 32, 32, 64].sample
    }
  end
)

def make_test_instance_hash(test_case, version, computer, passed, checksum,
  failure_type=nil, success_type=nil)

  runtimes = (45..2500).to_a

  rn_mem = rand(0.2..0.8) * computer[:model].ram_gb
  re_mem = rand(0.9..1.05) * rn_mem
  rn_time = runtimes.sample
  re_time = rand(0.1..0.2) * rn_time
  total_runtime = rand(1.05..1.10) * (rn_time + re_time)

  {
    test_case_id: test_case.id,
    computer_id: computer[:model].id,
    version_id: version.id,
    runtime_seconds: rn_time,
    mesa_version: version.number,
    omp_num_threads: computer[:threads],
    compiler: computer[:compiler],
    compiler_version: computer[:compiler_version],
    platform_version: computer[:platform_version],
    rn_mem: rn_mem,
    re_mem: re_mem,
    re_time: re_time,
    total_runtime_seconds: total_runtime,
    checksum: checksum,
    passed: passed,
    failure_type: failure_type,
    success_type: success_type
  }
end

def do_test_case_version(test_case, version, computer_data, num_passed,
                         checksum=nil)
  checksums = ('A'..'Z').to_a.map do |char|
    char*5
  end[0...(rand(2..num_passed))]
  success_type = %w(photo_checksum run_test_string).sample
  failure_types = %w(run_test_string photo_file photo_checksum compilation)
  passing = computer_data[0...(num_passed)]
  failing = computer_data[num_passed...computer_data.length]

  TestInstance.create!(
    passing.each_with_index.map do |computer, i|
      make_test_instance_hash(test_case, version, computer, true,
        checksum == :mixed ? checksums[i.modulo(checksums.length)] : checksums[0],
        failure_type = nil, success_type = success_type)
    end + 
    failing.each_with_index.map do |computer, i|
      make_test_instance_hash(test_case, version, computer, false, nil,
        failure_types.sample, nil)
    end
  )
end

def do_one_version(version_number)
  # 80% of versions will have multiple computers checking them
  multiple_computers = 0.8
  # 2% of versions will have compilation errors on any and all machines
  compilation_fail = 0.02

  # 20% of submitted versions will have a test case that fails on any and all
  # computers
  has_totally_failing_case = 0.2
  # 20% of submitted versions with more than one computer will have at least one
  # mixed test case
  has_mixed_failing_case = 0.2
  # 20% of submitted versions with more than one computer will have at least one
  # test case with multiple checksums
  has_checksum_case = 0.2
  # 20% of submitted versions with more than one computer will have at least one
  # case that has mixed passage AND mixed checksums
  has_mixed_and_checksum_case = 0.2

  if rand < multiple_computers
    these_computers = COMPUTERS.sample(rand(2..COMPUTERS.length))
    if rand < compilation_fail
      # just report failed compilations
      Version.create!(
        number: version_number,
        compile_fail_count: these_computers.length,
        compilation_status: 1
      )
      return
    end

    # set consistent compilers, compiler versions, and platform_versions
    computer_data = []
    thread_counts = [4, 6, 8, 10, 12]

    these_computers.each do |computer|
      threads = thread_counts[computer.name.hash.modulo(thread_counts.length)]
      compiler = (['gfortran', 'ifort'] + ['SDK'] * 10).sample
      compiler_version = case compiler
      when 'gfortran'
        ['8.3', '9.1.1'].sample
      when 'ifort'
        ['17.0', '18.0.1'].sample
      when 'SDK'
        case computer.platform
        when 'linux'
          'mesasdk-x86_64-linux-' + ['20190503', '20190404', '20190315'].sample
        else
          'mesasdk-x86_64-osx-' + ['10.10-10.14-20190503', '10.12-10.14-20190315',
                                   '10.14-20181104'].sample
        end
      end
      platform_version = case computer.platform
      when 'macOS'
        ['10.13.3', '10.14.2', '10.14.3', '10.14.5'][computer.name.hash.modulo(4)]
      else
        ['Ubuntu 16.04', 'Ubuntu 18.04', 'CentOS', 'Fedora 30'][computer.name.hash.modulo(4)]
      end
      computer_data << {
        model: computer,
        threads: threads,
        compiler: compiler,
        compiler_version: compiler_version,
        platform_version: platform_version
      }
    end


    # no compilation failures (note that there is no mixed compilation
    # situation here...)
    failing = []
    mixed = []
    checksums = []
    mixed_and_checksums = []
    if rand < has_totally_failing_case
      failing = TEST_CASES.sample(rand(1..8))
    end
    if rand < has_mixed_failing_case
      mixed = TEST_CASES.reject do |tc|
        failing.include? tc
      end.sample(rand(1..3))
    end
    if rand < has_checksum_case
      checksums = TEST_CASES.reject do |tc|
        failing.include?(tc) || mixed.include?(tc)
      end.sample(rand(1..3))
    end
    if rand < has_mixed_and_checksum_case && these_computers.length > 2
      mixed_and_checksums = TEST_CASES.reject do |tc|
        failing.include?(tc) || mixed.include?(tc) || checksums.include?(tc)
      end.sample(rand(1..3))
    end
    passing = TEST_CASES.reject do |tc|
      failing.include?(tc) || mixed.include?(tc) || checksums.include?(tc) ||
      mixed_and_checksums.include?(tc)
    end

    # Actually do database insertions
    version = Version.find_or_create_by(number: version_number)
    passing.each do |tc|
      do_test_case_version(tc, version, computer_data,
                           these_computers.length)
    end
    failing.each { |tc| do_test_case_version(tc, version, computer_data, 0) }
    mixed.each do |tc|
      do_test_case_version(tc, version, computer_data,
                           rand(1...these_computers.length))
    end
    checksums.each do |tc|
      do_test_case_version(tc, version, computer_data,
                           these_computers.length, :mixed)
    end

    mixed_and_checksums.each do |tc|
      do_test_case_version(tc, version, computer_data,
                           rand(2...these_computers.length), :mixed)
    end
  else
    if rand < compilation_fail
      # just report failed compilation
      Version.create!(
        number: version_number,
        compile_fail_count: 1,
        compilation_status: 1
      )
      return
    end

    comp = COMPUTERS.sample

    compiler = (['gfortran', 'ifort'] + ['SDK'] * 10).sample
    compiler_version = case compiler
    when 'gfortran'
      ['8.3', '9.1.1'].sample
    when 'ifort'
      ['17.0', '18.0.1'].sample
    when 'SDK'
      case comp.platform
      when 'linux'
        'mesasdk-x86_64-linux-' + ['20190503', '20190404', '20190315'].sample
      else
        'mesasdk-x86_64-osx-' + ['10.10-10.14-20190503', '10.12-10.14-20190315',
                                 '10.14-20181104'].sample
      end
    end
    platform_version = case comp.platform
    when 'macOS'
      ['10.13.3', '10.14.2', '10.14.3', '10.14.5'][comp.name.hash.modulo(4)]
    else
      ['Ubuntu 16.04', 'Ubuntu 18.04', 'CentOS', 'Fedora 30'][comp.name.hash.modulo(4)]
    end

    thread_counts = [4, 6, 8, 10, 12]
    threads = thread_counts[comp.name.hash.modulo(thread_counts.length)]

    this_computer = {
      model: comp,
      threads: threads,
      compiler: compiler,
      compiler_version: compiler_version,
      platform_version: platform_version
    }

    failing = []
    if rand < has_totally_failing_case
      failing = TEST_CASES.sample(rand(1..10))
    end

    passing = TEST_CASES.reject { |tc| failing.include? tc }

    # Actually do database insertions
    version = Version.find_or_create_by(number: version_number)
    passing.each { |tc| do_test_case_version(tc, version, [this_computer], 1) }
    failing.each { |tc| do_test_case_version(tc, version, [this_computer], 0) }
  end
end

11800.upto(11928) { |n| puts n; do_one_version(n) }

# populate test instances including a mix of the computers and test cases
# must also build test datum objects to include

####################################
#   instances of 1M_pre_ms_to_wd   #
####################################
# instance = TestInstance.create!(
#   runtime_seconds: 1500,
#   mesa_version: 10000,
#   omp_num_threads: 12,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: true,
#   test_case_id: test_cases[0].id,
#   computer_id: computers[0].id
# )
# instance.test_data.create(name: 'steps', integer_val: 24000)
# instance.test_data.create(name: 'retries', integer_val: 300)
# instance.test_data.create(name: 'backups', integer_val: 40)

# instance = TestInstance.create(
#   runtime_seconds: 2300,
#   mesa_version: 10000,
#   omp_num_threads: 4,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: true,
#   test_case_id: test_cases[0].id,
#   computer_id: computers[1].id
# )
# instance.test_data.create(name: 'steps', integer_val: 24000)
# instance.test_data.create(name: 'retries', integer_val: 300)
# instance.test_data.create(name: 'backups', integer_val: 40)
 
# #####################################
# #   instances of 15M_thermohaline   #
# #####################################
# instance = TestInstance.create(
#   runtime_seconds: 600,
#   mesa_version: 10000,
#   omp_num_threads: 12,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: false,
#   test_case_id: test_cases[1].id,
#   computer_id: computers[0].id
# )
# instance.test_data.create(name: 'steps', integer_val: 5000)
# instance.test_data.create(name: 'retries', integer_val: 30)
# instance.test_data.create(name: 'backups', integer_val: 4)

# ########################
# #   instances of wd2   #
# ########################
# instance = TestInstance.create(
#   runtime_seconds: 800,
#   mesa_version: 10000,
#   omp_num_threads: 12,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: true,
#   test_case_id: test_cases[2].id,
#   computer_id: computers[0].id
# )
# instance.test_data.create(name: 'steps', integer_val: 7000)
# instance.test_data.create(name: 'retries', integer_val: 100)
# instance.test_data.create(name: 'backups', integer_val: 20)

# instance = TestInstance.create(
#   runtime_seconds: 1200,
#   mesa_version: 10000,
#   omp_num_threads: 4,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: true,
#   test_case_id: test_cases[2].id,
#   computer_id: computers[1].id
# )
# instance.test_data.create(name: 'steps', integer_val: 7000)
# instance.test_data.create(name: 'retries', integer_val: 100)
# instance.test_data.create(name: 'backups', integer_val: 20)

# instance = TestInstance.create(
#   runtime_seconds: 900,
#   mesa_version: 10000,
#   omp_num_threads: 4,
#   compiler: 'ifort',
#   compiler_version: '17.0',
#   platform_version: '10.13',
#   passed: false,
#   test_case_id: test_cases[2].id,
#   computer_id: computers[2].id
# )
# instance.test_data.create(name: 'steps', integer_val: 7000)
# instance.test_data.create(name: 'retries', integer_val: 100)
# instance.test_data.create(name: 'backups', integer_val: 20)

# ##############################
# #   instances of wd_ignite   #
# ##############################
# instance = TestInstance.create(
#   runtime_seconds: 1200,
#   mesa_version: 10000,
#   omp_num_threads: 12,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: true,
#   test_case_id: test_cases[3].id,
#   computer_id: computers[0].id
# )
# instance.test_data.create(name: 'steps', integer_val: 9000)
# instance.test_data.create(name: 'retries', integer_val: 110)
# instance.test_data.create(name: 'backups', integer_val: 35)

# instance = TestInstance.create(
#   runtime_seconds: 2500,
#   mesa_version: 9795,
#   omp_num_threads: 12,
#   compiler: 'gfortran',
#   compiler_version: '7.2.0',
#   platform_version: '10.13',
#   passed: false,
#   test_case_id: test_cases[3].id,
#   computer_id: computers[0].id
# )
# instance.test_data.create(name: 'steps', integer_val: 800)
# instance.test_data.create(name: 'retries', integer_val: 1000)
# instance.test_data.create(name: 'backups', integer_val: 500)
