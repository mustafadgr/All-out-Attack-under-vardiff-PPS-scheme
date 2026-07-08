function results = PPS_all_out_simulator(T_share,num_epochs,alpha,beta,T_B,p_1,D_0)
% PPS All-Out Attack simulator
%
% T_share            : attacker's target share interval (sec)
% num_epochs         : number of epochs
% alpha              : attacker hashpower fraction
% beta               : honest victim pool hashpower
% T_B                : target block interval (sec)
% p1                 : attacker fraction infiltrating victim pool
% D_0                : accepted blocks per epoch


%% Initialization

% Initial network block generation rate (blocks/sec)
lambda_block = 1/T_B;

% Pool is configured so that every miner submits one share every T_share
% seconds on average at the initial network difficulty.
share_rate = 1/T_share;

% Normalized network block difficulty. Difficulty is updated after every
% epoch according to Bitcoin's difficulty adjustment algorithm.
block_difficulty = 1;

% Global simulation clock.
time = 0;

% Normalize each canonical block reward to one unit.
block_reward = 1;

% Statistical value (difficulty) of a single submitted share for the
% adversary and the honest victim-pool miners at the initial difficulty.
adv_share_difficulty = alpha*p_1*T_share/T_B;
hon_pool_miners_share_difficulty = beta*T_share/T_B;

adv_reward = 0;
hon_pool_miners_reward = 0;
rest_reward = 0;
operator_profit = 0;

difficulty_hist = zeros(num_epochs,1);
epoch_time_hist = zeros(num_epochs,1);
adv_reward_hist = zeros(num_epochs,1);
pool_reward_hist = zeros(num_epochs,1);
rest_reward_hist = zeros(num_epochs,1);
operator_profit_hist = zeros(num_epochs,1);
discarded_blocks_hist = zeros(num_epochs,1);

%% Epoch loop

% Each epoch terminates after D_0 accepted (canonical) blocks, exactly as
% in Bitcoin. Withheld blocks do not contribute toward the epoch length.

for epoch = 1:num_epochs

    accepted_blocks = 0;
    discarded_blocks = 0;
    epoch_time = 0;
    
    % PPS reward per submitted share.
    %
    % The pool keeps the target share interval fixed (T_share), therefore
    % the share difficulty remains unchanged throughout the simulation.
    % However, after each network difficulty adjustment, every submitted
    % share represents a larger fraction of the block difficulty.
    % Consequently, the PPS reward per share scales inversely with the
    % current block difficulty.
    
    adv_reward_per_share = block_reward*adv_share_difficulty/block_difficulty;
    hon_pool_miners_reward_per_share = block_reward*hon_pool_miners_share_difficulty/block_difficulty;

    while accepted_blocks < D_0

        %% Next block arrival

        % Generate the next network block arrival according to the current
        % network difficulty.

        dt = exprnd(1/(lambda_block/block_difficulty));
        
        time = time + dt;
        epoch_time = epoch_time + dt;

        %% Adversary submits PPS shares during dt

        % Shares submitted by the infiltrating adversary during the current
        % inter-block interval. Every submitted share receives an immediate
        % PPS payment from the pool operator.

        num_adv_Shares = poissrnd(share_rate*dt);
        adv_reward = adv_reward + adv_reward_per_share*num_adv_Shares;
        operator_profit = operator_profit - adv_reward_per_share*num_adv_Shares;
        
        % Honest victim-pool miners also submit shares according to the
        % same target share interval.
        
        num_hon_pool_miners_Shares = poissrnd(share_rate*dt);
        hon_pool_miners_reward = hon_pool_miners_reward + hon_pool_miners_reward_per_share*num_hon_pool_miners_Shares;
        operator_profit = operator_profit - hon_pool_miners_reward_per_share*num_hon_pool_miners_Shares;
        
        %% Determine block finder

        % Sample the miner who finds the next block according to the global
        % hashpower distribution.

        u = rand;

        if u < alpha*p_1

            % Infiltrating attacker finds a valid block.
            % The block is withheld and discarded, therefore it does not
            % contribute to the blockchain nor toward the current epoch.

            discarded_blocks = discarded_blocks + 1;

        elseif u < alpha

            % Honest attacker (solo mining) finds a canonical block.

            accepted_blocks = accepted_blocks + 1;
            adv_reward = adv_reward + block_reward;

        elseif u < alpha + beta

            % Honest victim pool finds a canonical block.
            % The pool operator receives the block reward and additionally
            % rewards the miner for the submitted full-PoW share.
            
            accepted_blocks = accepted_blocks + 1;           
            operator_profit = operator_profit + block_reward;
            
            hon_pool_miners_reward = hon_pool_miners_reward + hon_pool_miners_reward_per_share;
        else

            % Honest miners outside the victim pool find the block.

            accepted_blocks = accepted_blocks + 1;
            rest_reward = rest_reward + block_reward;

        end

    end

    %% Bitcoin difficulty adjustment

    % Difficulty is adjusted using Bitcoin's rule:
    % new difficulty = old difficulty × target epoch time / actual epoch time.
    %
    % Therefore, if block withholding causes the epoch to take longer than
    % expected, the network difficulty decreases for the next epoch.

    target_epoch_time = D_0*T_B;

    block_difficulty = block_difficulty*(target_epoch_time/epoch_time);

    %% Store statistics

    difficulty_hist(epoch) = block_difficulty;
    epoch_time_hist(epoch) = epoch_time;

    adv_reward_hist(epoch) = adv_reward;
    pool_reward_hist(epoch) = hon_pool_miners_reward;
    rest_reward_hist(epoch) = rest_reward;
    operator_profit_hist(epoch) = operator_profit;

    discarded_blocks_hist(epoch) = discarded_blocks;

end

%% Output

% Normalize cumulative rewards by D_0 so that one epoch corresponds to a
% total block reward of one, matching the normalization used in the paper.

scale = D_0;


results.adv_reward_history = adv_reward_hist/scale;
results.pool_reward_history = pool_reward_hist/scale;
results.rest_reward_history = rest_reward_hist/scale;
results.operator_profit_history = operator_profit_hist/scale;

results.difficulty = difficulty_hist;
results.epoch_time = epoch_time_hist/target_epoch_time;
results.discarded_blocks = discarded_blocks_hist/D_0;

%% Expected honest strategy rewards (paper normalization)

% Expected cumulative rewards if every miner followed the honest strategy.
% Since rewards accumulate proportionally with elapsed time, the baseline
% is computed using the normalized cumulative epoch durations rather than
% simply the epoch index.

cum_time = cumsum(results.epoch_time);

results.expected_honest.adv_reward = alpha * cum_time;
results.expected_honest.pool_reward = beta * cum_time;
results.expected_honest.rest_reward = (1-alpha-beta) * cum_time;
results.expected_honest.operator_profit = zeros(num_epochs,1);

end