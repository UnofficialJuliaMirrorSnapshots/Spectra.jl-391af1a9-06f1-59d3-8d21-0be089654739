#############################################################################
#Copyright (c) 2016 Charles Le Losq
#
#The MIT License (MIT)
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the #Software without restriction, including without limitation the rights to use, copy, #modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, #and to permit persons to whom the Software is furnished to do so, subject to the #following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, #INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# diffusion.jl contains several functions focused on the treatment of infrared spectra along diffusion profiles in minerals
#
#
#############################################################################
"""
The 'IRdataprep' function allows to obtain the frequency, distance and y vectors in a region of interest, ready to input in an optimisation algorithm.

   IRdataprep(data,distance_step,start_sp,stop_sp,low_x,high_x,norm_low_x,norm_high_x)
with
data (array, Float64): an array containing in the first column the x values and in the subsequent columns the correcponding intensities;
distance_step (Float64): the steps between each spectrum along the diffusion profile, in metres;
start_sp and stop_sp (Int): the starting and stopping spectra of interest (warning: number of data columns - 1, as data also contains the x axis such that size(data)[2] = number of spectras + 1);
low_x,high_x (Float64): frequencies between which the signal is of interest, defined as low_x < high_x;
norm_low_x and norm_high_x (Float64): frequencies between which the signal must be integrated for mormalising the final signals.

This function first checks that the x values are increasing, and correct that if this is not the case.

Then, it selects the data in the region of interest, delimited by frequencies defined as low_x < high_x.
Normalisation to the area between the norm_low_x and norm_high_x frequency is also performed (norm_low_x < norm_high_x)

The code returns the x and the y arrays, plus arrays for optimisation: x_input_fit contains the frequency-distance couples and y_input_fit their corresponding y values.
"""
function IRdataprep(data::Array{Float64},distance_step::Float64,spectra_numbers::Array{Int64}, portion_interest::Array{Float64}, normalization_region::Array{Float64},integration_regions::Array{Float64},polarizer_orientation::AbstractString;fig_select::Int64=1,bas_switch::AbstractString = "No",roi::Array{Float64} = [3000. 3100.; 3425. 3530.; 3630. 3650.],baseline_type = "gcvspline", smoothing_coef = 10.0, Spline_Order = 3,noise_estimation = "No", noise_calculation_portion::Array{Float64} = [3000. 3100.])
	
    start_sp::Int = spectra_numbers[1]
    stop_sp::Int = spectra_numbers[2]
    low_x::Float64 = portion_interest[1]
    high_x::Float64 = portion_interest[2]
    norm_low_x::Float64 = normalization_region[1]
    norm_high_x::Float64 = normalization_region[2]
    ese_low_x::Float64 = noise_calculation_portion[1]
    ese_high_x::Float64 = noise_calculation_portion[2]
	
    if data[end,1] <= data[1,1]
        data=data[end:-1:1,:]
        data[data[:,:] .== 0]= 1e-20# to avoid pure 0 values
    end
   
    x::Array{Float64} = data[find(low_x .< data[:,1] .< high_x),1]
    x_sili::Array{Float64} = data[find(norm_low_x .< data[:,1] .< norm_high_x),1]
 
    if stop_sp .>= size(data,2)
        y::Array{Float64} = data[find(low_x .< data[:,1] .< high_x),start_sp:end]
        y_sili::Array{Float64} = data[find(norm_low_x .< data[:,1] .< norm_high_x),start_sp:end]
        if noise_estimation == "Yes"
            ese::Array{Float64} =  std(data[find(ese_low_x .< data[:,1] .< ese_high_x),start_sp:end],1) #relative error
            y_ese_r::Array{Float64} = ese[1,:]./y[:,:]  
        end
    else
        y = data[find(low_x .< data[:,1] .< high_x),start_sp:stop_sp]
        y_sili = data[find(norm_low_x .< data[:,1] .< norm_high_x),start_sp:stop_sp]
		if noise_estimation == "Yes"
            ese =  std(data[find(ese_low_x .< data[:,1] .< ese_high_x),start_sp:stop_sp],1) #relative error
        	y_ese_r = ese[1,:]./y[:,:]
        end
        
    end
	
	nb_exp = size(y,2)
	nb_points = size(y,1)
   
   # integration of silicate bands for normalisation depending on the polariser orientation, we use different thickness determination
    if polarizer_orientation == "A"
        K1 = 0.8345
    elseif polarizer_orientation == "C"
        K1 = 0.5620
    end
   
    for i = 1:nb_exp
		y_sili_corr,~ = baseline(x_sili[:,1],y_sili[:,i],[norm_low_x norm_low_x+5;norm_high_x-5 norm_high_x],"poly",p=1.0)
        y[:,i] = y[:,i]./(trapz(x_sili[:,1],y_sili_corr[:,1])./K1.*1e-4) # integration of silicate bands for normalisation, thickness is in cm
    end

    if (bas_switch == "Yes") && (roi[1,1] != 0)
        data_bas = ones(size(y))
        base = ones(size(y))
        for i = 1:nb_exp
			data_bas[:,i], base[:,i] = baseline(x, y[:,i],roi,baseline_type,p=smoothing_coef,SplOrder=Spline_Order)
			#for k = 1:size(roi,1)-1
			#	data_bas[roi[k,1] .<= x .<= roi[k+1,2],i], base[roi[k,1] .<= x .<= roi[k+1,2],i] = baseline(x[roi[k,1] .<= x .<= roi[k+1,2]], y[roi[k,1] .<= x .<= roi[k+1,2],i],roi[k:k+1,:],baseline_type,p=smoothing_coef)
			#end
        end
	   
        figure()
        plot(x,y[:,fig_select],"k-",label="Data")
        plot(x,base[:,fig_select+1],"b-",label="Baseline")
        y = data_bas
        plot(x,y[:,fig_select],"g-",label="Corrected")
		legend(loc="best")
    end

   # constructing the good distance vector + X and Y associated values
    steps::Float64 = 0.0
	integrale_matrix::Array{Float64} = zeros(nb_exp,size(integration_regions,1))
	distance_vector::Array{Float64} = zeros(nb_exp)
    y_interest::Array{Float64} = zeros(nb_points,nb_exp)
    ese_y_interest::Array{Float64} = zeros(length(x),1)
	
    for i = 1:nb_exp
        
		distance_vector[i] = steps # individual distance vector
		for k = 1:size(integration_regions,1)
			integrale_matrix[i,k] = trapz(x[integration_regions[k,1] .<= x .<= integration_regions[k,2]],y[integration_regions[k,1] .<= x .<= integration_regions[k,2],i])
		end
		
        steps = steps + distance_step
    end
   
	if noise_estimation == "Yes"
        #return x, y, y_ese_r, distance_vector, integrale_matrix
    else
        return x, y, distance_vector, integrale_matrix
	end
end

"""
The `peak_diffusion` function allows to fit/plot gaussian peaks for which the amplitude is defined by a 1D diffusion law
Call as:
    peak_diffusion(g_c0::Array{Float64,1},g_c1::Array{Float64,1},g_D::Array{Float64,1}, g_freq::Array{Float64,1}, g_hwhm::Array{Float64,1},x::Array{Float64,2},time::Float64)

where:
g_c0 is the vector of concentration imposed, at the diffusive bondary (a.u., float64 number);
g_c1 is the vector of initial concentration in the host (a.u., float64 number);
g_D is the vector of diffusivity coefficient, in log units
g_freq is the vector containing the frequencies fo the peaks
g_hwhm is the vector containing the hwhm of the peaks
x is an array containing the distances and associated frequencies
time is the duration of the run in seconds

The function returns a vector of the values of the peak intensity at the input frequencies.

The current version assumes the peak being a Gaussian peak. Updates will integrate Lorentzian and Pseudo-Voigt peaks.
"""
function peak_diffusion(g_c0::Array{Float64,1},g_c1::Array{Float64,1},g_D::Array{Float64,1}, g_freq::Array{Float64,1}, g_hwhm::Array{Float64,1},x::Array{Float64,2},time::Float64)
    segments = zeros(size(x)[1],size(g_c0)[1])
    for i = 1:size(g_c0)[1]
        segments[:,i] = ((g_c1[i] - g_c0[i]) .* erfc(x[:,1]./(2. .* sqrt( 10.0 .^g_D[i] .* time))) + g_c0[i]) .*exp(-log(2) .* ((x[:,2]-g_freq[i]) ./g_hwhm[i]) .^2)
    end
    return sum(segments,2), segments
end

"""
The global model for using with the Julia.optim package. Not necessarily up to date because I prefer using the JuMP way.
   model(p,x_fit,temps;compo_out = 0)
"""
function model(p::Array{Float64,1},x_fit::Array{Float64,2},temps::Float64;compo_out::Int = 0)
    number_gauss = length(p)/5
    components = zeros(length(x_fit[:,2]),round(Int8,number_gauss))
    compteur = 1
    for i = 1:5:length(p)
        components[:,compteur] = peak_diffusion(x_fit[:,1],temps,x_fit[:,2],p[i],p[i+1],p[i+2],p[i+3],p[i+4])
        compteur = compteur + 1
    end
    if compo_out == 0
        return sum(components,2)
    else
        return components
    end
end

